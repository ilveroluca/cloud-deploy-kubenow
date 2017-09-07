FROM python:2.7-alpine3.6
MAINTAINER "Anders Larsson <anders.larsson@icm.uu.se>"

# Provisioners versions
ENV TERRAFORM_VERSION=0.9.11
ENV TERRAFORM_SHA256SUM=804d31cfa5fee5c2b1bff7816b64f0e26b1d766ac347c67091adccc2626e16f3
ENV ANSIBLE_VERSION=2.3.1.0
ENV LIBCLOUD_VERSION=1.5.0
ENV J2CLI_VERSION=0.3.1.post0
ENV DNSPYTHON_VERSION=1.15.0
ENV JMESPATH_VERSION=0.9.3
ENV SHADE_VERSION=1.21.0
ENV OPENSTACKCLIENT_VERSION=3.11.0

# Install APK deps
RUN apk add --update --no-cache \
  git \
  curl \
  openssh \
  build-base \
  linux-headers \
  libffi-dev \
  openssl-dev \
  openssl \
  bash \
  su-exec \
  apache2-utils \
  libvirt \
  libvirt-dev \
  cdrkit

# Install PIP deps
RUN pip install \
  ansible=="$ANSIBLE_VERSION" \
  j2cli=="$J2CLI_VERSION" \
  dnspython=="$DNSPYTHON_VERSION" \
  jmespath=="$JMESPATH_VERSION" \
  apache-libcloud=="$LIBCLOUD_VERSION" \
  shade=="$SHADE_VERSION"

# Install Terraform
RUN curl "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" > \
    "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" && \
    echo "${TERRAFORM_SHA256SUM}  terraform_${TERRAFORM_VERSION}_linux_amd64.zip" > \
    "terraform_${TERRAFORM_VERSION}_SHA256SUMS" && \
    sha256sum -c "terraform_${TERRAFORM_VERSION}_SHA256SUMS" && \
    unzip "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -d /bin && \
    rm -f "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"

# Build and install terraform-libvirt plugin
RUN apk add --update --no-cache pkgconfig go && \
    go get github.com/dmacvicar/terraform-provider-libvirt && \
    cp $HOME/go/bin/terraform-provider-libvirt /bin && \
    apk del go && \
    rm -rf $HOME/go

# Copy script
COPY bin/docker-entrypoint-v2 /

# Set entrypoint
ENTRYPOINT ["/docker-entrypoint-v2"]
