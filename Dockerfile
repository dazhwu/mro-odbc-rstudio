FROM ubuntu:16.04



## (Based on https://github.com/rocker-org/rocker/blob/master/r-base/Dockerfile
## https://github.com/blueogive/mro-docker
## https://github.com/akzaidi/mrclient-rstudio)
## Set a default user. Available via runtime flag `--user docker`
## Add user to 'staff' group, granting them write privileges to /usr/local/lib/R/site.library
## User should also have & own a home directory (e.g. for linked volumes to work properly).

RUN apt-get update -qq \
	&& apt-get dist-upgrade -y \
	&& apt-get install -y make gcc gfortran libunwind8 gettext libssl-dev libcurl3-dev zlib1g libicu-dev \
	wget curl tcl8.6 xvfb xauth apt-transport-https libclang-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

#    Microsoft R Client
#	&& wget http://packages.microsoft.com/config/ubuntu/16.04/packages-microsoft-prod.deb  \
#	&& dpkg -i packages-microsoft-prod.deb \
#	&& apt-get update \
#	&& apt-get install -y microsoft-r-client-packages-3.5.2 


RUN set -e \
      && useradd -m -d /home/rstudio rstudio \
      && echo rstudio:ropen1 \
        | chpasswd   \
&& addgroup rstudio staff

WORKDIR /home/rstudio


## Install Microsoft ODBC driver for SQL Server
RUN curl -o microsoft.asc https://packages.microsoft.com/keys/microsoft.asc \
    && apt-key add microsoft.asc \
    && rm microsoft.asc \
    && curl https://packages.microsoft.com/config/ubuntu/16.04/prod.list > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql17 unixodbc-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV MRO_VERSION=3.5.3
ENV RSTUDIO_VERSION=1.3.959 
ENV    PATH=/usr/lib/rstudio-server/bin:$PATH
ENV RSTUDIO_URL="https://download2.rstudio.org/server/xenial/amd64/rstudio-server-${RSTUDIO_VERSION}-amd64.deb"
ENV R_LIBS_USER=/home/rstudio/R/lib

WORKDIR /home/rstudio

## Download and install MRO & MKL
RUN curl -LO -# https://mran.blob.core.windows.net/install/mro/${MRO_VERSION}/ubuntu/microsoft-r-open-${MRO_VERSION}.tar.gz \
    && tar -xzf microsoft-r-open-${MRO_VERSION}.tar.gz
WORKDIR /home/rstudio/microsoft-r-open
RUN ./install.sh -a -u

# Clean up downloaded files and install libpng
WORKDIR /home/rstudio
RUN rm microsoft-r-open-*.tar.gz && \
    rm -r microsoft-r-open 

# Print EULAs on every start of R to the user, because they were accepted at image build time
COPY EULA.txt MRC_EULA.txt
COPY MKL_EULA.txt MKL_EULA.txt
COPY MRO_EULA.txt MRO_EULA.txt




COPY Renviron.site Renviron.site
RUN  echo "R_LIBS_USER=${R_LIBS_USER}" >> Renviron.site \
&& mv Renviron.site /opt/microsoft/ropen/$MRO_VERSION/lib64/R/etc \
&&  echo 'options("download.file.method" = "libcurl")' >> /opt/microsoft/ropen/$MRO_VERSION/lib64/R/etc/Rprofile.site


 

RUN mkdir -p --mode 755 /home/rstudio/.checkpoint && \
 chown -R rstudio:rstudio /home/rstudio/.checkpoint && \
    mkdir -p --mode 775 /home/rstudio/work /home/rstudio/R  ${R_LIBS_USER} && \
chown -R rstudio:rstudio /home/rstudio    




##&& \
 ##chown -R rstudio:rstudio /home/rstudio/R && \
 ##chown -R rstudio:rstudio ${R_LIBS_USER}




COPY rpkgs.csv rpkgs.csv 
COPY Rpkg_install.R Rpkg_install.R  

RUN xvfb-run Rscript Rpkg_install.R  \
&& rm rpkgs.csv Rpkg_install.R  

WORKDIR /tmp

# install rstudio server
RUN apt-get update \
        && apt-get install -y --no-install-recommends \
        file \
        git \
        libapparmor1 \
        libedit2 \
        libcurl4-openssl-dev \
        libssl-dev \
        lsb-release \
        psmisc \
        python-setuptools \
        sudo \
        gdebi-core \
        wget \
        libssl-dev \
        gfortran \
        build-essential \
        libxml2-dev \
        tzdata \
  && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
       
RUN   wget -q $RSTUDIO_URL \
  && gdebi --option=APT::Get::force-yes=1,APT::Get::Assume-Yes=1 -n rstudio-server-*-amd64.deb \
  && rm rstudio-server-*-amd64.deb  \
&&    rm -rf /tmp/*


EXPOSE 8787

WORKDIR /home/rstudio
## RUN chown -R rstudio:rstudio /home/rstudio/

#RUN echo "rsession-which-r=/opt/microsoft/ropen/${MRO_VERSION}/lib64/R" >> /etc/rstudio/rserver.conf


## RStudio wants an /etc/R, will populate from $R_HOME/etc
RUN ln -s /opt/microsoft/ropen/${MRO_VERSION}/lib64/R/etc /etc/R \
  && echo '\n\
    \n# Configure httr to perform out-of-band authentication if HTTR_LOCALHOST \
    \n# is not set since a redirect to localhost may not work depending upon \
    \n# where this Docker container is running. \
    \nif(is.na(Sys.getenv("HTTR_LOCALHOST", unset=NA))) { \
    \n  options(httr_oob_default = TRUE) \
    \n}' >> /etc/R/Rprofile.site \
  && echo "PATH=${PATH}" >> /etc/R/Renviron 
  

## Prevent rstudio from deciding to use /usr/bin/R if a user apt-get installs a package
RUN echo 'rsession-which-r=/usr/bin/R' >> /etc/rstudio/rserver.conf \
  ## use more robust file locking to avoid errors when using shared volumes:
  && echo 'lock-type=advisory' >> /etc/rstudio/file-locks


#RUN echo "rsession-which-r=/opt/microsoft/rclient/3.5.2/bin/R/R" >> /etc/rstudio/rserver.conf
#RUN echo "r-libs-user=/opt/microsoft/rclient/3.5.2/libraries/RServer" >> /etc/rstudio/rsession.conf


CMD ["/usr/lib/rstudio-server/bin/rserver", "--server-daemonize=0", "--server-app-armor-enabled=0"]


