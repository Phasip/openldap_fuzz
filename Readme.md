# Warning: Not tested after rename of stuff and removal of internal stuff. May need some massage.
# Currently input_fuzz.tar.bz2 is not included, create your own intitial inputs. (Hopefully to be added later)

## Building
    cd openldap_fuzz
    git clone https://github.com/openldap/openldap
    cd openldap
    patch -p1 < ../fuzzing.patch
    cd ..
    tar xvf input_fuzz.tar.bz2
    docker build -t openldap_fuzz .
    
## Running
    # This is a ugly hack because I don't want to write pretty scripts
    PREP_CMD="cp -r /tmpfs_init/* /tmpfs/"
    # TODO: change -v /root/fuzzdata to where you have the data & inputs ( containers looking for /fuzzing/openldap_fuzz/input_fuzz )
    DFLAGS="-v /root/fuzzdata/:/fuzzing --net=host --pid=host --ipc=host --uts=host --log-driver=none --rm --privileged -it --tmpfs /tmpfs --tmpfs /usr/local/var/run --user=root openldap_fuzz"
    AFLFLAGS="PYTHONPATH=/ AFL_MAP_SIZE=328792 AFL_TMPDIR=/tmpfs AFL_AUTORESUME=1 "
    
    #--Launch all the runners-- 
    screen -d -m -S leader /usr/bin/docker run $DFLAGS "$PREP_CMD; $AFLFLAGS afl-fuzz -b1 -i /fuzzing/openldap_fuzz/input_fuzz -o /fuzzing/outputs_fuzz -m 3024 -M $ARCH-leader -- /openldap/servers/slapd/fuzzing.ngram; exec bash"
    for i in $(seq 2 5 $(nproc)); do screen -d -m -S minion$i /usr/bin/docker run $DFLAGS "$PREP_CMD; $AFLFLAGS afl-fuzz -b$i -i /fuzzing/openldap_fuzz/input_fuzz -o /fuzzing/outputs_fuzz -m 3024 -S $ARCH-minion$i -- /openldap/servers/slapd/fuzzing.lto-laf; exec bash"; done
    for i in $(seq 3 5 $(nproc)); do screen -d -m -S minion$i /usr/bin/docker run $DFLAGS "$PREP_CMD; $AFLFLAGS AFL_CUSTOM_MUTATOR_LIBRARY='/AFLplusplus/custom_mutators/radamsa/radamsa-mutator.so;/AFLplusplus/custom_mutators/libfuzzer/libfuzzer-mutator.so' afl-fuzz -b$i -i /fuzzing/openldap_fuzz/input_fuzz -o /fuzzing/outputs_fuzz -m 3024 -S $ARCH-minion$i -- /openldap/servers/slapd/fuzzing.lto-laf; exec bash"; done
    for i in $(seq 4 5 $(nproc)); do screen -d -m -S minion$i /usr/bin/docker run $DFLAGS "$PREP_CMD; $AFLFLAGS afl-fuzz -D -b$i -i /fuzzing/openldap_fuzz/input_fuzz -o /fuzzing/outputs_fuzz -m 3024 -S $ARCH-minion$i -- /openldap/servers/slapd/fuzzing.lto-laf; exec bash"; done
    for i in $(seq 5 5 $(nproc)); do screen -d -m -S minion$i /usr/bin/docker run $DFLAGS "$PREP_CMD; $AFLFLAGS afl-fuzz -b$i -i /fuzzing/openldap_fuzz/input_fuzz -o /fuzzing/outputs_fuzz -m 3024 -S $ARCH-minion$i -c /openldap/servers/slapd/fuzzing.lto-cmplog -- /openldap/servers/slapd/fuzzing.lto; exec bash"; done
    for i in $(seq 6 5 $(nproc)); do screen -d -m -S minion$i /usr/bin/docker run $DFLAGS "$PREP_CMD; $AFLFLAGS afl-fuzz -b$i -i /fuzzing/openldap_fuzz/input_fuzz -o /fuzzing/outputs_fuzz -m 3024 -S $ARCH-minion$i -- /openldap/servers/slapd/fuzzing.ngram; exec bash"; done
    
## Crash triage
    docker run $DFLAGS "$PREP_CMD; bash"
    find /fuzzing/outputs_fuzz/ -wholename \*crashes/id\* -exec /bin/sh -c '/openldap/servers/slapd/fuzzing.debug < "{}" 1>/dev/null 2>/tmpfs/out; echo "{}:$?"' \; | grep -v ':0$' | rev | cut -d: -f2- | rev | tee /fuzzing/crashing_files
    for f in $(cat /fuzzing/crashing_files); do gdb /openldap/servers/slapd/fuzzing.debug -ex 'set pagination off' -ex 'set confirm off' -ex "set args < $f" -ex run -ex 'bt 8' -ex quit 2>&1 | grep -E ') at |program: |fuzzing.debug: | signal |) from '; done | tee /fuzzing/errors

## Info
    docker run $DFLAGS "afl-whatsup /fuzzing/outputs_fuzz"

## Quit that shit
    screen -S leader -X quit
    for i in $(seq 2 $(nproc)); do screen -S minion$i -X quit; done

## TODO
    Don't use a static ldap_init, use slapadd to configure the container
