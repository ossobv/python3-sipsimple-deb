python3-sipsimple-deb :: OSSO build of AG-Projects sipsimple packages
=====================================================================

Getting working deb packages for *Ubuntu/Jammy* was not entirely
trivial. The official repository had a broken release file [1].

[1] https://ag-projects.com/ubuntu/dists/jammy/Release content is equal
to the index view of the parent directory. (Last checked 2022-10-12.)

Additionally, getting ``python3-sipsimple`` to work as simple package
was less than trivial because of the mandatory ``python3-*``
dependencies.

This project builds ``python3-sipsimple*.deb`` and the appropriate
dependencies for Ubuntu/Jammy.

*AG-Projects sipsimple* already contains build scripts for *Debian*, so most
of is (re)used verbatim.

Usage::

    ./Dockerfile.build

Results:

.. code-block:: console

    $ cd Dockerfile.out/jammy/python3-sipsimple_5.2.6+2+g1e60156a-0osso0+ubu22.04

    $ ls -1 *.deb
    python3-application_3.0.3_all.deb
    python3-eventlib_0.3.0_all.deb
    python3-gnutls_3.1.7_all.deb
    python3-msrplib_0.21.1_all.deb
    python3-otr_2.0.0_all.deb
    python3-sipsimple_5.2.6+2+g1e60156a-0osso0+ubu22.04_amd64.deb
    python3-xcaplib_2.0.0_all.deb

These packages can then be installed/uninstalled easily. (You may need
to ``apt-get -f install`` to fix dependencies if you're installing them
from the filesystem using ``dpkg -i``.)
