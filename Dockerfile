FROM registry.access.redhat.com/ubi8/ubi

# Go paths
ENV GOPATH /go
ENV GOROOT /usr/local/go

# Gem paths
ENV GEM_PATH /usr/local/rvm/gems/ruby-2.3.2:/usr/local/rvm/gems/ruby-2.3.2@global
ENV GEM_HOME /usr/local/rvm/gems/ruby-2.3.2

ENV PATH $GOPATH/bin:$GOROOT/bin:/opt:/usr/local/rvm/bin:/usr/local/rvm/gems/ruby-2.3.2/bin:/usr/local/rvm/gems/ruby-2.3.2@global/bin:/usr/local/rvm/rubies/ruby-2.3.2/bin:$PATH

ENV GOLANG_VERSION 1.13.5
ENV GOLANG_DOWNLOAD_URL https://golang.org/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz

ENV GCLOUD_SDK_VERSION 270.0.0
ENV GCLOUD_SDK_DOWNLOAD_URL https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-${GCLOUD_SDK_VERSION}-linux-x86_64.tar.gz

ENV GIT_VERSION 2.9.5
ENV GIT_DOWNLOAD_URL https://www.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.gz

ENV HELM_VERSION 2.15.2
ENV HELM_DOWNLOAD_URL https://storage.googleapis.com/kubernetes-helm/helm-v${HELM_VERSION}-linux-amd64.tar.gz

# add the Centos-8 repos
ADD ./centos8.repo /etc/yum.repos.d/centos8.repo

# sudo-devel only comes from centos-base, it's not available in the UBI repos,
# so we have to install both of sudo and sudo-devel 1.8.23 from Centos 7 repos
# bash-4.4# yum --showduplicates list sudo sudo-devel libpcap  | expand
# Available Packages
# libpcap.i686                       14:1.5.3-11.el7                  centos-base
# libpcap.x86_64                     14:1.5.3-11.el7                  centos-base
# libpcap.i686                       14:1.9.0-1.el8                   ubi-8-baseos
# libpcap.x86_64                     14:1.9.0-1.el8                   @System
# libpcap.x86_64                     14:1.9.0-1.el8                   ubi-8-baseos
# sudo.x86_64                        1.8.23-3.el7                     centos-base
# sudo.x86_64                        1.8.25p1-4.el8                   ubi-8-baseos
# sudo-devel.i686                    1.8.23-3.el7                     centos-base
# sudo-devel.x86_64                  1.8.23-3.el7                     centos-base

## Dependencies - I override multilib version checking since it wants
## different versions of libpcap for 32bit and 64bit which it normally won't allow
## but we only build for 64bit so it doesn't matter here in the builder image
#
## ruby and ruby-devel 2.0.0.648-35 both come from centos  Ubi7 has ruby only, no ruby-devel,
## and they are different versions so a conflict occurs if I don't specify the version here
#
# Centos 8 repos also provide
#   libpcap-devel
#   gettext-devel
#   sudo-devel

RUN yum update -y \
    && yum install -y  --exclude=systemd* --setopt=protected_multilib=false \
    #    libpcap-2.22-9.el7.x86_64 \
    #    libpcap-devel-2.22-9.el7.x86_64 \
    #    ruby-2.0.0.648-35.el7_6.x86_64 \
    #    ruby-devel-2.0.0.648-35.el7_6.x86_64 \
       libpcap \
       libpcap-devel \
       ruby \
       ruby-devel \
       openssl-devel \
       curl-devel \
       expat-devel \
       gettext-devel \
       zlib-devel \
       perl \
       perl-ExtUtils-MakeMaker \
       # sudo-devel \  Not in Centos 8
       gcc-c++ \
       gcc \
       make \
       yum-utils \
       device-mapper-persistent-data \
       lvm2 \
       iproute \
       container-selinux \
       procps-ng \
    && dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo \
    && dnf install -y --nobest docker-ce \
    && ( docker version || true )

## install a recent git
RUN mkdir -p /usr/src 2>/dev/null 1>&2 \
    && curl -fsSL ${GIT_DOWNLOAD_URL} | tar -xz -C /usr/src \
    && cd /usr/src/git-${GIT_VERSION} \
    && make -j4 prefix=/usr/local NO_SVN_TESTS=1 NO_TCLTK=1 all \
    && make prefix=/usr/local NO_SVN_TESTS=1 NO_TCLTK=1 install \
    && git --version

## install a recent helm
RUN curl -sSL ${HELM_DOWNLOAD_URL} | tar -xz -C /tmp \
    && mv /tmp/linux-amd64/helm /usr/local/bin \
    && rm -rf /tmp/linux-amd64 \
    && chmod 755 /usr/local/bin/helm \
    && helm init --client-only

## GCloud
RUN mkdir -p /opt \
    && curl -sSL ${GCLOUD_SDK_DOWNLOAD_URL} | tar -xz -C /opt \
    && ln -s /opt/google-cloud-sdk/bin/gcloud /usr/local/bin/ \
    && ln -s /opt/google-cloud-sdk/bin/gsutil /usr/local/bin/

## Go (NOTE: all the rm is due to a poor golang install on base image)
RUN rm -rf $GOROOT $GOPATH /root/go /root/go1.10.1.linux-amd64.tar.gz && \
    curl -fsSL ${GOLANG_DOWNLOAD_URL} | tar -xz -C /usr/local \
    && mkdir -p "$GOPATH/src" "$GOPATH/bin"

## Go Tools
RUN go get -u \
    github.com/magefile/mage \
    github.com/golangci/golangci-lint/cmd/golangci-lint \
    github.com/tebeka/go2xunit \
    github.com/smartystreets/goconvey/convey \
    github.com/alecthomas/gometalinter \
    github.com/golang/mock/gomock \
    golang.org/x/lint/golint \
    golang.org/x/tools/cmd/cover \
    golang.org/x/tools/cmd/goimports \
    github.com/golang/dep/cmd/dep \
    github.com/aporeto-inc/go-bindata/... \
  && gometalinter --install

RUN echo >> /root/.bashrc
RUN echo 'echo $GITCREDS > ~/.gitcreds' >> /root/.bashrc
RUN echo "git config --global credential.helper 'store --file ~/.gitcreds' /root/.bashrc" >> /root/.bashrc

WORKDIR $GOPATH
