python3-sipsimple-deb :: OSSO build of SIPSIMPLE
================================================

*AG Projects* has built `SIP SIMPLE <https://sipsimpleclient.org/>`_, an SDK to interface with *VoIP* devices.

Download and installation instructions are `here
<http://download.ag-projects.com/SipSimpleSDK/Python3/>`_, but they are
slightly outdated and do not work properly for *Ubuntu/Jammy*.

For one, the `debian packages
<https://ag-projects.com/ubuntu/dists/jammy/>`_ appeared to include
*jammy*, but the ``Releases`` file was broken (returned the index
itself). Further, the installation wasn't really clear on which
dependencies are needed.

The ``python3-sipsimple-deb`` project is a way to consistently build
``python3-sipsimple`` and the required dependencies in one go for Debian
and Ubuntu platforms. It uses the *Debian* build scripts already included
by *AG Projects* as much as possible.

Usage::

    ./Dockerfile.build

Results:

.. code-block:: console

    $ cd Dockerfile.out/jammy/python3-sipsimple_5.2.6+2+g1e60156a-0osso0+ubu22.04

    $ ls -1 *.deb
    python3-application_3.0.4_all.deb
    python3-eventlib_0.3.0_all.deb
    python3-gnutls_3.1.10_all.deb
    python3-msrplib_0.21.1_all.deb
    python3-otr_2.0.1_all.deb
    python3-sipsimple_5.2.6+2+g1e60156a-0osso0+ubu22.04_amd64.deb
    python3-xcaplib_2.0.1_all.deb

These packages can then be installed/uninstalled easily. (You may need
to ``apt-get -f install`` to fix dependencies if you're installing them
from the filesystem using ``dpkg -i``.)


Examples
--------

See `<example.py>`_ for a very basic calling example. This example was
taken from `saghul's sipsimple_hello_world.py
<https://github.com/saghul/sipsimple-examples/blob/master/sipsimple_hello_world.py>`_
and adapted so it works with python3-sipsimple.
