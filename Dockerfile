# syntax=docker/dockerfile:experimental

# Copyright (c) 2019, NVIDIA CORPORATION. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ARG BASE_IMAGE=nvcr.io/nvidia/pytorch:20.01-py3

# build an image that includes only the nemo dependencies, ensures that dependencies
# are included first for optimal caching, and useful for building a development
# image (by specifying build target as `nemo-deps`)
FROM ${BASE_IMAGE} as nemo-deps

# Ensure apt-get won't prompt for selecting options
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y \
    libsndfile1 sox \
    python-setuptools \
    python-dev ffmpeg && \
    rm -rf /var/lib/apt/lists/*

# install trt
ENV PATH=$PATH:/usr/src/tensorrt/bin
WORKDIR /tmp/trt-oss
ARG NV_REPO=https://developer.download.nvidia.com/compute/machine-learning/repos/ubuntu1804/x86_64

RUN cd /tmp/trt-oss
ARG DEB=libcudnn7_7.6.5.32-1+cuda10.2_amd64.deb
RUN curl -sL --output ${DEB} ${NV_REPO}/${DEB}
ARG DEB=libnvinfer7_7.0.0-1+cuda10.2_amd64.deb
RUN curl -sL --output ${DEB} ${NV_REPO}/${DEB}
ARG DEB=libnvinfer-plugin7_7.0.0-1+cuda10.2_amd64.deb
RUN curl -sL --output ${DEB} ${NV_REPO}/${DEB}
ARG DEB=libnvonnxparsers7_7.0.0-1+cuda10.2_amd64.deb
RUN curl -sL --output ${DEB} ${NV_REPO}/${DEB}
ARG DEB=python-libnvinfer_7.0.0-1+cuda10.2_amd64.deb
RUN curl -sL --output ${DEB} ${NV_REPO}/${DEB}
RUN dpkg -i *.deb && cd ../.. && rm -rf /tmp/trt-oss

# install nemo dependencies
WORKDIR /tmp/nemo
RUN pip install torch==1.5.0+cu101 torchvision==0.6.0+cu101 -f https://download.pytorch.org/whl/torch_stable.html
COPY requirements/requirements_docker.txt requirements.txt
RUN pip install --disable-pip-version-check --no-cache-dir -r requirements.txt

# copy nemo source into a scratch image
FROM scratch as nemo-src
COPY . .

# start building the final container
FROM nemo-deps as nemo
ARG NEMO_VERSION
ARG BASE_IMAGE

# Check that NEMO_VERSION is set. Build will fail without this. Expose NEMO and base container
# version information as runtime environment variable for introspection purposes
RUN /usr/bin/test -n "$NEMO_VERSION" && \
    /bin/echo "export NEMO_VERSION=${NEMO_VERSION}" >> /root/.bashrc && \
    /bin/echo "export BASE_IMAGE=${BASE_IMAGE}" >> /root/.bashrc
RUN --mount=from=nemo-src,target=/tmp/nemo cd /tmp/nemo && pip install ".[all]"
RUN apt-get -y install unzip
# RUN apt-get update && apt-get -y install cron

# copy scripts/examples/tests into container for end user
WORKDIR /workspace/nemo
COPY scripts /workspace/nemo/scripts
COPY examples /workspace/nemo/examples
COPY tests /workspace/nemo/tests
COPY README.rst LICENSE /workspace/nemo/
# Copy hello-cron file to the cron.d directory
#RUN cp scripts/sena/checkpoint-crontab /etc/cron.d/checkpoint-crontab

# Give execution rights on the cron job
#RUN chmod 0644 /etc/cron.d/checkpoint-crontab

# Apply cron job
#RUN crontab /etc/cron.d/checkpoint-crontab

# copying necessary manifests
WORKDIR /workspace/nemo/scripts

# Script for providing manifest(Meta data used in NeMo) from original dataset from Mozilla (TSV)
#This file will be Half of the total Traning set (120.000 records)
RUN wget https://speech-datasets-c6cb1c99e61f.s3.amazonaws.com/NeMo-persian.zip
RUN unzip NeMo-persian.zip && rm NeMo-persian.zip

WORKDIR /workspace/nemo
RUN git clone https://github.com/shokuie/sena_nemo.git

# Create the log file to be able to run tail
RUN printf "#!/bin/bash\njupyter lab --no-browser --allow-root --ip=0.0.0.0" >> start-jupyter.sh && \
    chmod +x start-jupyter.sh

