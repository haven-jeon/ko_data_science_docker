
#텐서플로 mxnet 동시 지원 도커 이미지로 시작 
FROM nvidia/cuda:8.0-cudnn6-devel-ubuntu16.04

LABEL maintainer="gogamza <madjakarta@gmail.com>"


ARG PY_VER=3.6


USER root


RUN apt-get update && apt-get -yq dist-upgrade && \
  apt-get install -yq --no-install-recommends \
    wget git vim apt-transport-https \
    bzip2 ssh \
    ca-certificates \
    sudo \
    locales \
    fonts-liberation \
    fonts-nanum-coding && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

#로케일설정  
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen


# Install Tini... 간헐적 좀비 프로세스 생성 방지 
RUN wget --quiet https://github.com/krallin/tini/releases/download/v0.10.0/tini && \
    echo "1361527f39190a7338a0b434bd8c88ff7233ce7b9a4876f3315c22fce7eca1b0 *tini" | sha256sum -c - && \
    mv tini /usr/local/bin/tini && \
    chmod +x /usr/local/bin/tini



#R 커널 설치 
RUN apt-get update && \
  echo "deb https://cran.rstudio.org/bin/linux/ubuntu xenial/" >> /etc/apt/sources.list && \
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E084DAB9  && \
  apt-get update && \
  apt-get -y install r-base-dev r-base && \
  apt-get -y install software-properties-common && \
  add-apt-repository ppa:jonathonf/python-$PY_VER -y && \
  apt-get update && \
  apt-get -y install python$PY_VER-dev python$PY_VER-venv && \
  apt-get -y install libopenblas-dev curl && \
  add-apt-repository ppa:openjdk-r/ppa  && \
  apt-get update && \
  apt-get -y install openjdk-9-jdk-headless && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  curl https://bootstrap.pypa.io/get-pip.py | python$PY_VER


# 환경 변수 
ENV VENV_DIR=/opt/venv \
    SHELL=/bin/bash \
    NB_USER=gogamza \
    NB_UID=1000 \
    NB_GID=100 \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8
ENV PATH=$VENV_DIR/bin:$PATH \
    HOME=/home/$NB_USER \
    LD_LIBRARY_PATH="/usr/local/lib/:${LD_LIBRARY_PATH}"


ADD fix-permissions /usr/local/bin/fix-permissions
# Create gogamza user with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
#사용자 권한 및 계정 설정 
RUN useradd -m -s /bin/bash -N -u $NB_UID $NB_USER && \
    mkdir -p $VENV_DIR && \
    chown $NB_USER:$NB_GID $VENV_DIR && \
    fix-permissions $HOME && \
    fix-permissions $VENV_DIR

#몇몇 일반적으로 활용되는 R 패키지를 설치한다. 
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		littler libxml2-dev libcairo2-dev libsqlite-dev libmariadbd-dev libmariadb-client-lgpl-dev libpq-dev libssh2-1-dev libcurl4-openssl-dev \
                r-cran-littler \
		r-base \
		r-base-dev \
		r-recommended \
        && echo 'options(repos = c(CRAN = "https://cran.rstudio.com/"), download.file.method = "libcurl")' >> /etc/R/Rprofile.site \
        && echo 'source("/etc/R/Rprofile.site")' >> /etc/littler.r \
	&& ln -s /usr/share/doc/littler/examples/install.r /usr/local/bin/install.r \
	&& ln -s /usr/share/doc/littler/examples/install2.r /usr/local/bin/install2.r \
	&& ln -s /usr/share/doc/littler/examples/installGithub.r /usr/local/bin/installGithub.r \
	&& ln -s /usr/share/doc/littler/examples/testInstalled.r /usr/local/bin/testInstalled.r \
	&& install.r docopt tidyverse dplyr ggplot2 devtools formatR remotes selectr caTools data.table  \
	&& rm -rf /tmp/downloaded_packages/ /tmp/*.rds \
	&& rm -rf /var/lib/apt/lists/*



USER $NB_USER

# Setup work directory for backward-compatibility
#virtualenv로 개인 권한 내에서  파이썬 설치 
RUN mkdir /home/$NB_USER/work && \
    fix-permissions /home/$NB_USER && \
    python$PY_VER -m venv $VENV_DIR && \
    /bin/bash -c "source $VENV_DIR/bin/activate"

#추후 python의 경우 GPU버전과 CPU버전의 이미지 분리가 필요함 
RUN pip$PY_VER install --upgrade pip && \
    pip$PY_VER install --no-cache-dir tqdm jpype1 konlpy pandas scipy numpy tensorflow-gpu \
      keras jupyter jupyterhub jupyter_contrib_nbextensions \
      jupyter_nbextensions_configurator jupyterlab jupyterthemes \
      sklearn matplotlib seaborn rpy2 gensim  opencv-python scikit-image  && \ 
    pip$PY_VER install --no-cache-dir mxnet-cu80 --pre && \
    jupyter serverextension enable --py jupyterlab --sys-prefix && \
    jupyter nbextensions_configurator enable --user && \
    jupyter nbextension install https://github.com/ipython-contrib/IPython-notebook-extensions/archive/master.zip --user && \
    jupyter nbextension install https://github.com/Calysto/notebook-extensions/archive/master.zip --user



#주피터랩  테마 복사/ 개인 편집 가능  

RUN mkdir -p $HOME/.jupyter/lab/user-settings/\@jupyterlab/apputils-extension && \
    mkdir -p $HOME/.jupyter/nbconfig/ && \
    mkdir -p $HOME/.config/matplotlib/

COPY notebook.json $HOME/.jupyter/nbconfig/
COPY matplotlibrc $HOME/.config/matplotlib/
COPY themes.jupyterlab-settings $HOME/.jupyter/lab/user-settings/\@jupyterlab/apputils-extension/

#주피터 테마설정 
RUN jt -t chesterish -fs 95 -cellw 95% -T -tfs 11 -nfs 115 -f bitstream

#권한 체크 및 변경/ 오래 걸림 
RUN fix-permissions $VENV_DIR && \
    fix-permissions $HOME/.jupyter/ 

USER root


#jupyter R 커널 설치
RUN (echo "devtools::install_github('IRkernel/IRkernel')" && \
     echo "IRkernel::installspec()") \
    | Rscript -e "source(file('stdin'))" && \
    R CMD javareconf  

#install konlpy mecab
RUN curl -fSsL -O https://raw.githubusercontent.com/konlpy/konlpy/master/scripts/mecab.sh && \
    chmod +x mecab.sh && \
    ./mecab.sh


RUN mkdir -p $HOME/py_libs/lib/python$PY_VER/site-packages && \
    fix-permissions $HOME/py_libs/ && \
    echo 'PYTHONUSERBASE='$HOME'/py_libs/\n'\
         'PYTHONPATH='$HOME'/py_libs/lib/python'$PY_VER'/site-packages\n'\
         'JUPYTER_PATH='$HOME'/py_libs/lib/python'$PY_VER'/site-packages\n'\
          >>  /etc/environment



EXPOSE 8888-9000
WORKDIR $HOME

# Configure container startup
ENTRYPOINT ["tini", "--"]
CMD ["start-notebook.sh"]

# Add local files as late as possible to avoid cache busting
COPY start-notebook.sh  /usr/local/bin/
COPY start.sh  /usr/local/bin/
COPY start-singleuser.sh  /usr/local/bin/
COPY jupyter_notebook_config.py  /etc/jupyter/
RUN fix-permissions  /etc/jupyter/ && \
    fix-permissions $HOME/.jupyter/ 

#time zone 
ENV TZ=Asia/Seoul
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

#mxnet 환경 변수 
#ENV MXNET_CUDNN_AUTOTUNE_DEFAULT=1 \
#    MXNET_ENGINE_TYPE=ThreadedEngine

#ENV CUDA_DEVICE_ORDER=PCI_BUS_ID \
#    CUDA_VISIBLE_DEVICES='1,0'


# Switch back to gogamza to avoid accidental container runs as root
USER $NB_USER

ENV PYTHONUSERBASE=$HOME/py_libs/
ENV PYTHONPATH=$PYTHONUSERBASE/lib/python$PY_VER/site-packages:$PYTHONPATH


