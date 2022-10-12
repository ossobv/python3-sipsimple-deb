"""
-------------------------
Initial SIPSIMPLE example
-------------------------

What does it do:
Default account (alice, see example.d config) calls sip:bob@example.com.

Setup of configuration file:
http://projects.ag-projects.com/projects/sipsimpleclient/wiki/SipConfigurationAPI#Account

```sh
mkdir example.d

cat >example.d/config <<EOF
Accounts:
    alice@example.com:
        display_name = Alice
        enabled = True
        auth:
            password = 'secret_alice_password'
            username = alice

SIPSimpleSettings:
    default_account = alice@example.com
EOF
```

Originally sipsimple_hello_world.py from
https://github.com/saghul/sipsimple-examples
"""
import os.path
from threading import Event

from gevent import monkey

# Do this before importing anything else. Needed because python3-xcaplib does
# this too, but then it is too late.
monkey.patch_socket()
monkey.patch_ssl()

if True:  # E402 module level import not at top of file
    from application.notification import NotificationCenter

    from sipsimple.account import AccountManager
    from sipsimple.audio import WavePlayer, WavePlayerError
    from sipsimple.application import SIPApplication
    from sipsimple.configuration import ConfigurationManager
    from sipsimple.core import SIPURI, ToHeader
    from sipsimple.lookup import DNSLookup, DNSLookupError
    from sipsimple.session import Session
    from sipsimple.storage import FileStorage
    from sipsimple.streams.rtp.audio import AudioStream
    from sipsimple.threading.green import run_in_green_thread

CONFIGURATION_DIR = 'example.d'
AUDIO_FILE = os.path.realpath(
    os.path.join(os.path.dirname(__file__), 'example.wav'))


class SimpleCallApplication(SIPApplication):
    def __init__(self):
        super().__init__()
        self.started = Event()
        self.ended = Event()
        self.callee = None
        self.session = None
        self.player = None
        notification_center = NotificationCenter()
        notification_center.add_observer(self)

    def call(self, callee):
        self.callee = callee
        self.start(FileStorage(CONFIGURATION_DIR))

    @run_in_green_thread
    def _NH_SIPApplicationDidStart(self, notification):
        self.callee = ToHeader(SIPURI.parse(self.callee))
        try:
            routes = DNSLookup().lookup_sip_proxy(
                self.callee.uri, ['udp']).wait()
        except DNSLookupError as e:
            print('DNS lookup failed: %s' % str(e))
        else:
            account = AccountManager().default_account
            self.session = Session(account)
            self.session.connect(self.callee, routes, [AudioStream()])

    def _NH_SIPSessionGotRingIndication(self, notification):
        print('Ringing! --', notification.name, notification.data)

    def _NH_SIPSessionDidStart(self, notification):
        print('Session started! --', notification.name, notification.data)
        session = notification.sender
        audio_stream = session.streams[0]
        player = WavePlayer(
            audio_stream.mixer, AUDIO_FILE, loop_count=3, initial_delay=1)
        audio_stream.bridge.add(player)
        print('  bridge contents =', [
            i().__class__.__name__ for i in audio_stream.bridge.ports])
        try:
            print('Player starting', player, AUDIO_FILE)
            player.play()
        except WavePlayerError as e:
            print('Player error', repr(e))
            audio_stream.bridge.remove(player)
            session.end()
        else:
            self.player = player
        self.started.set()

    def _NH_SIPSessionDidFail(self, notification):
        print('Failed to connect! --', notification.name, notification.data)
        self.stop()

    def _NH_SIPSessionDidEnd(self, notification):
        print('Session ended! --', notification.name, notification.data)
        session = notification.sender
        audio_stream = session.streams[0]
        print('  bridge contents =', [
            i().__class__.__name__ for i in audio_stream.bridge.ports])
        self.stop()

    def _NH_SIPApplicationDidEnd(self, notification):
        print('Application ended! --', notification.name, notification.data)
        self.started.set()
        self.ended.set()


# Place a call to the specified URI
application = SimpleCallApplication()

print('Placing call...')
application.call('sip:bob@example.com')

if False:
    cm = ConfigurationManager()
    cm.save()
if False:
    am = AccountManager()
    acc = am.get_account('alice@example.com')
    print(acc)

application.started.wait()

if application.player:
    import sys
    import time
    while application.player.is_active:
        time.sleep(0.5)  # yuck.. don't do blocking sleep
        sys.stderr.write('.')
        sys.stderr.flush()
    sys.stderr.write('\n')
    if application.session:
        application.session.end()

application.ended.wait()
