ARG osdistro=ubuntu
ARG oscodename=jammy

FROM $osdistro:$oscodename
LABEL maintainer="Walter Doekes <wjdoekes+sipsimple@osso.nl>"
LABEL dockerfile-vcs=https://github.com/ossobv/python3-sipsimple

ARG DEBIAN_FRONTEND=noninteractive

# This time no "keeping the build small". We only use this container for
# building/testing and not for running, so we can keep files like apt
# cache. We do this before copying anything and before getting lots of
# ARGs from the user. That keeps this bit cached.
RUN echo 'APT::Install-Recommends "0";' >/etc/apt/apt.conf.d/01norecommends
# We'll be ignoring "debconf: delaying package configuration, since
# apt-utils is not installed"
RUN apt-get update -q && \
    apt-get dist-upgrade -y && \
    apt-get install -y \
        bzip2 ca-certificates curl git jq wget \
        build-essential dh-autoreconf devscripts dpkg-dev equivs quilt

# Set up build env
RUN printf "%s\n" \
    QUILT_PATCHES=debian/patches \
    QUILT_NO_DIFF_INDEX=1 \
    QUILT_NO_DIFF_TIMESTAMPS=1 \
    'QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index"' \
    'QUILT_DIFF_OPTS="--show-c-function"' \
    >~/.quiltrc

# Apt-get prerequisites according to control file.
ARG upname
COPY source-files/${upname}/debian/control /build/debian/control
RUN mk-build-deps --install --remove --tool "apt-get -y" /build/debian/control

# ubuntu, ubu, jammy, python3-sipsimple, 5.2.6, '', 0osso0
ARG osdistro osdistshort oscodename upname upversion debepoch= debversion

# Copy debian dir, set/check version
RUN mkdir -p /build/debian
COPY source-files/${upname}/debian/changelog /build/debian/changelog
RUN . /etc/os-release && sed -i -e "\
        1s/([^)]*)/(${upversion}-${debversion}+${osdistshort}${VERSION_ID})/;\
        1s/) unstable;/) ${oscodename};/" \
        /build/debian/changelog && \
    fullversion="${upversion}-${debversion}+${osdistshort}${VERSION_ID}" && \
    expected="${upname} (${debepoch}${fullversion}) ${oscodename}; urgency=medium" && \
    head -n1 /build/debian/changelog && \
    if test "$(head -n1 /build/debian/changelog)" != "${expected}"; \
    then echo "${expected}  <-- mismatch" >&2; false; fi

# Set up upstream source and jump into dir.
COPY ./source-files/${upname}/ /build/${upname}
WORKDIR /build/${upname}

# Make a clean reproducible tar, with 1970 timestamps, sorted, etc..
RUN ./get_dependencies.sh && rm -v deps/*.tar.*
RUN git clean -dfx --exclude=debian/ --exclude=deps/ && \
    # Record SOURCE_VERSION of all git dependencies
    find . -name '.git' | \
      xargs --no-run-if-empty -IX env DIR='X' sh -c 'DIR=${DIR%/.git} && git -C "$DIR" show >"$DIR/SOURCE_VERSION"' && \
    # (reproducible tar, with 1970 timestamps, sorted, etc..)
    cd .. && \
    find ${upname} '!' '(' \
      -type d -o -name .gitignore -o -name .gitmodules -o -path '*/.git/*' \
      -o -name '*.srctrl*' -o -name '*.rej' -o -name '*.orig' -o -name '*.o' -o -name '*.pyc' ')' \
      -print0 | LC_ALL=C sort -z | tar -cf ${upname}_${upversion}.orig.tar \
      --numeric-owner --owner=0 --group=0 --mtime='1970-01-01 00:00:00' \
      --no-recursion --null --files-from - && \
    gzip --no-name ${upname}_${upversion}.orig.tar

# Alter existing debian dir with our modified changelog.
RUN cp /build/debian/changelog debian/changelog
RUN echo '3.0 (quilt)' >debian/source/format

# Fetch mandatory dependencies so we can build deb packages for those too:
# - python3-application
# - python3-eventlib
# - python3-gnutls
# - python3-otr
# - python3-msrplib
# - python3-xcaplib
ENV ALSO_BUILD_PROJECTS="python3-application python3-eventlib python3-gnutls \
    python3-otr python3-msrplib python3-xcaplib"
# Extra deps for (at least) python3-application and python3-otr and
# python3-xcaplib. (Quick fix. Should read control file here too...)
RUN apt-get install -qy python3-gevent python3-gmpy2 python3-greenlet \
      python3-lxml python3-setuptools python3-twisted
# These are old. Take them from github instead.
# tars=$(wget -qO- http://download.ag-projects.com/SipSimpleSDK/Python3/ | \
# sed -e '/<a href=/!d;s/.*<a href="//;s/".*//;/python3/!d;/sipsimple/d'); \
# for tar in $tars; do \
#   wget http://download.ag-projects.com/SipSimpleSDK/Python3/$tar; done
# Fetch tags lists first so we don't hit the rate limits that hard.
RUN cd /build && \
    echo "== READING GITHUB API ==================================" >&2 && \
    for project in $ALSO_BUILD_PROJECTS; do \
        mkdir "$project" && \
        echo "https://api.github.com/repos/AGProjects/$project/tags" && \
        curl -sSfLo "$project/tags" "https://api.github.com/repos/AGProjects/$project/tags" && \
        echo || { ret=$?; break; }; \
    done && test -z $ret
RUN cd /build && \
    echo "== FETCHING LATEST TARBALLS ============================" >&2 && \
    for project in $ALSO_BUILD_PROJECTS; do \
        echo "https://api.github.com/repos/AGProjects/$project/tags" && \
        tags=$(cat "$project/tags") && \
        # Some projects (python3-xcaplib) have both release-X and X. Do
        # complicated stuff to get the latest of either.
        case $project in \
        python3-eventlib) \
            # Removing 0.8.11 because it's older than 0.2.5 :(
            latest=$(printf '%s\n' "$tags" | jq -r '.[].name' | sed -e 's/^release-//;/^[0-9]/!d;/^0[.]8[.]11/d' | sort -rV | head -n1);; \
        python3-msrplib) \
            # Someone forgot to push the 0.21.1 tag
            latest=$({ printf '%s\n' "$tags" | jq -r '.[].name'; echo 0.21.1; } | \
              sed -e 's/^release-//;/^[0-9]/!d' | sort -rV | head -n1);; \
        *) \
            latest=$(printf '%s\n' "$tags" | jq -r '.[].name' | sed -e 's/^release-//;/^[0-9]/!d' | sort -rV | head -n1);; \
        esac && \
        tar=$(printf '%s\n' "$tags" | jq -r '.[] | select(.name == "'$latest'" or .name == "release-'$latest'") | .tarball_url') && \
        if test -z "$tar"; then \
            # Most files here are older, except python3-msrplib-0.21.1
            tar=http://download.ag-projects.com/SipSimpleSDK/Python3/$project-$latest.tar.gz; \
        fi && \
        filename="${project}-${latest}_orig.tar.gz" && \
        echo "latest: $latest -- source: $tar" && \
        curl -sSfLo "$project/$filename" "$tar" && \
        test -s "$project/$filename" && file "$project/$filename" && \
        echo || { ret=$?; break; }; \
    done && test -z $ret
# Make debs for all dependencies and install them locally immediately.
# The dependencies are mandatory for certain dh_test scripts.
RUN echo "== EXTRACTING AND BUILDING =============================" >&2 && \
    for project in $ALSO_BUILD_PROJECTS; do \
        cd /build/$project && \
        tar zxf *.tar.gz && find . -type f 2>&1 && \
        dir=$(find . -maxdepth 1 -mindepth 1 -type d) && \
        cd "$dir" && dpkg-buildpackage -us -uc && cd .. && \
        ls >&2 && dpkg -i *.deb && mv ${project}* .. && cd .. && \
        echo || { ret=$?; break; }; \
    done && test -z $ret
# Install all dependencies, not just Build-Depends, as done by
# mk-build-deps above. We need all of these to satisfy the dh_test
# scripts. (This is a bug, those packages should be listed in Build-Depends.)
# Without these, we'd need 'nocheck' in DEB_BUILD_OPTIONS.
RUN apt-get install -qy $(sed -e '\
    /^Depends:/,/^[^[:blank:]]/!d; \
    /^\(Depends:\|^[[:blank:]]\)/!d; \
    s/^Depends://; \
    s/\${[^}]*}//g; \
    s/,/ /g' debian/control)


###############################################################################
# Build
###############################################################################
# Instead of
#   RUN DEB_BUILD_OPTIONS=parallel=6 dpkg-buildpackage -us -uc
# we split up the steps for Docker.
#
# Answer by "the paul" to question by "Dan Kegel":
# https://stackoverflow.com/questions/15079207/debhelper-deprecated-option-until
#
# Last modified by wdoekes, at 2022-06-01.
###############################################################################
# $ sed -e '/run_\(cmd\|hook\)(/!d;s/^[[:blank:]]*/  /' \
#     $(command -v dpkg-buildpackage)
#   run_hook('init', 1);
#   run_cmd('dpkg-source', @source_opts, '--before-build', '.');
#   run_hook('preclean', $preclean);
#   run_hook('source', build_has_any(BUILD_SOURCE));
#   run_cmd('dpkg-source', @source_opts, '-b', '.');
#     ^- dpkg-buildpackage --build=source
#   run_hook('build', build_has_any(BUILD_BINARY));
#   run_cmd(@debian_rules, $buildtarget) if rules_requires_root($binarytarget);
#     ^- dpkg-buildpackage -nc -T build
#   run_hook('binary', 1);
#     ^- dpkg-buildpackage -nc --build=any,all -us -uc
#   run_hook('buildinfo', 1);
#   run_cmd('dpkg-genbuildinfo', @buildinfo_opts);
#   run_hook('changes', 1);
#   run_hook('postclean', $postclean);
#   run_cmd('dpkg-source', @source_opts, '--after-build', '.');
#     ^- also done AFTER source build, so we need to --before-build again
#   run_hook('check', $check_command);
#   run_cmd($check_command, @check_opts, $chg);
#   run_hook('sign', $signsource || $signbuildinfo || $signchanges);
#   run_hook('done', 1);
#   run_cmd(@cmd);
#   run_cmd($cmd);
###############################################################################
ENV DEB_BUILD_OPTIONS="parallel=6"
# (1) check build deps, clean tree, make source debs;
#     we abuse the hook to exit after the build, so we can continue without
#     having to re-do any --before-build and clean.
RUN dpkg-buildpackage --build=source --hook-buildinfo="sh -c 'exit 69'" || \
      rc=$?; test ${rc:-0} -eq 69
# (2) perform build (make);
#     /tmp/fail so we can inspect the result of a failed build if we want
RUN dpkg-buildpackage --no-pre-clean --rules-target=build || touch /tmp/fail
RUN ! test -f /tmp/fail
# (3) install stuff into temp dir, tar it up, make the deb file (make install);
#     /tmp/fail so we can inspect the result of a failed build if we want
RUN dpkg-buildpackage --no-pre-clean --build=any,all -us -uc || touch /tmp/fail
RUN ! test -f /tmp/fail
# (4) reconstruct the changes+buildinfo files, adding the source build;
#     the binary buildinfo has SOURCE_DATE_EPOCH in the Environment, we'll
#     want to keep that.
RUN changes=$(ls ../${upname}*.changes) && \
    buildinfo=$(ls ../${upname}*.buildinfo) && \
    dpkg-genchanges -sa >$changes && \
    restore_env=$(sed -e '/^Environment:/,$!d' $buildinfo) && \
    dpkg-genbuildinfo && \
    remove_env=$(sed -e '/^Environment:/,$!d' $buildinfo) && \
    echo "$remove_env" | sed -e 's/^/-/' >&2 && \
    echo "$restore_env" | sed -e 's/^/+/' >&2 && \
    sed -i -e '/^Environment:/,$d' $buildinfo && \
    echo "$restore_env" >>$buildinfo
###############################################################################

# TODO: for bonus points, we could run quick tests here;
# for starters dpkg -i tests?

# Write output files (store build args in ENV first).
ENV oscodename=$oscodename osdistshort=$osdistshort \
    upname=$upname upversion=$upversion debversion=$debversion
RUN . /etc/os-release && \
    fullversion=${upversion}-${debversion}+${osdistshort}${VERSION_ID} && \
    mkdir -p /dist/${upname}_${fullversion} && \
    mv /build/${upname}_${upversion}.orig.tar.gz \
        /dist/${upname}_${fullversion}/ && \
    find /build -maxdepth 1 -type f -print0 | \
        xargs -0 -IX mv X /dist/${upname}_${fullversion}/ && \
    cd / && find dist/${upname}_${fullversion} -type f >&2
