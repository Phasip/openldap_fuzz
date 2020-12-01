FROM aflplusplus/aflplusplus
RUN cd /AFLplusplus/custom_mutators/radamsa/; make
RUN cd /AFLplusplus/custom_mutators/libfuzzer/; make
COPY ldap_init /tmpfs_init
ARG DEBIAN_FRONTEND=noninteractive
WORKDIR /
VOLUME /tmpfs
RUN rm -rf /etc/ldap /var/lib/ldap /usr/local/etc/openldap /usr/local/var/openldap-data;\
        mkdir -p /usr/local/var/ /usr/local/etc  \
    &&  ln -s /tmpfs/ldap_etc /usr/local/etc/openldap \
    &&  ln -s /tmpfs/ldap_data /usr/local/var/openldap-data

RUN apt-get update && \
    apt-get install -y libltdl-dev groff-base uuid-dev libuuid1 git netcat gdb

RUN apt-get install -y python3-pip \
    && pip3 install asn1 

COPY openldap /openldap

# Build a few versions of the target
ARG AFL_LLVM_INSTRUMENT=CFG
ARG AFL_HARDEN=1
RUN sed 's/MAP_SIZE_POW2 16/MAP_SIZE_POW2 18/g' /AFLplusplus/include/config.h
RUN sed 's/MAP_SIZE_POW2 16/MAP_SIZE_POW2 18/g' /AFLplusplus/config.h

RUN CC=gcc CFLAGS='-g -O0' /openldap/buildfuzz.sh fuzzing.debug
RUN cp -r /openldap /openldap_clean\
    && cd /openldap_clean\
    && git stash\
    && echo "int main(){}" > /openldap_clean/servers/slapd/fuzzing.c
    && CC=gcc CFLAGS='-g -O0' /openldap_clean/buildfuzz.sh deleteme
ARG CC=afl-clang-lto
ARG CFLAGS='-g -O3 -fsanitize-coverage-blocklist=/openldap/afl_ignore.txt'
RUN /openldap/buildfuzz.sh fuzzing.lto
RUN AFL_LLVM_LAF_ALL=1 /openldap/buildfuzz.sh fuzzing.lto-laf
RUN AFL_LLVM_CMPLOG=1 /openldap/buildfuzz.sh fuzzing.lto-cmplog       
RUN CC=afl-clang-fast AFL_LLVM_NGRAM_SIZE=4 /openldap/buildfuzz.sh fuzzing.ngram
ENTRYPOINT ["/bin/bash", "-c"]
