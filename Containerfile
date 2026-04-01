# Copyright 2026, Technical University of Munich
# Copyright 2026, Politecnico di Milano.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0. You may obtain a
# copy of the License at
#
# https://solderpad.org/licenses/SHL-2.1/
#
# Unless required by applicable law or agreed to in writing, any work
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# ----------
#
# CROSS - Codes and Restricted Objects Signature Scheme
#
# @version 1.0 (April 2026)
#
# @author: Francesco Antognazza <francesco.antognazza@polimi.it>

FROM docker.io/debian:latest

ARG TARGETPLATFORM

ENV DEBIAN_FRONTEND=noninteractive
ENV VERIBLE_VERSION=0.0-4051-g9fdb4057
ENV VERIBLE_TARGET_OS=linux-static

RUN apt update \
    && apt install --no-install-recommends -y \
        nodejs \
        git \
        zstd \
        build-essential \
        make \
        cmake \
        ninja-build \
        g++ \
        ccache \
        default-jre \
        antlr4 \
        curl \
        bzip2 \
        zlib1g \
        zlib1g-dev \
        libb64-dev \
        libssl-dev \
        uuid-dev \
        libantlr4-runtime-dev \
    && apt clean \
    && rm -rf /var/lib/apt/lists/*

RUN case ${TARGETPLATFORM} in \
         "linux/amd64")  VERIBLE_ARCH=x86_64  ;; \
         "linux/arm64")  VERIBLE_ARCH=arm64  ;; \
    esac \
    && echo "Fetching Verible release from https://github.com/chipsalliance/verible/releases/download/v${VERIBLE_VERSION}/verible-v${VERIBLE_VERSION}-${VERIBLE_TARGET_OS}-${VERIBLE_ARCH}.tar.gz" \
    && curl -s -L https://github.com/chipsalliance/verible/releases/download/v${VERIBLE_VERSION}/verible-v${VERIBLE_VERSION}-${VERIBLE_TARGET_OS}-${VERIBLE_ARCH}.tar.gz \
    | tar -xvkz -C / --strip-components 1

WORKDIR /work
ENTRYPOINT ["/bin/bash"]
