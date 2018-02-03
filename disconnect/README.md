Disconnect Test
===============

The purpose of this test is to verify the correct behavior of the explicit device
removal mechanism.


## Scenarios

Currently, three test scenarios are defined:

 1. Detach the tested device.
 2. Take the tested device offline and detach it.
 3. Take the tested device offline, bring it online and detach it.


## Judging Success

In all scenarios, the criteria for success are very similar. There has to be no
crash of the HC driver, device driver or other system component. In addition,
the performed activities must complete successfully (i.e. no deadlock, failure).


## Usage

The test is performed by a shell script. Symlink the `test.sh` file to your
HelenOS repo root and modify configuration by setting the environment variables
in the beginning of the script.

The default configuration is as follows:

```shell
# Which host controllers to test.
HCS="uhci ohci ehci xhci"

# Which QEMU devices to test (the "usb-" prefix is dropped).
DEVS="mouse kbd tablet tmon"

# Which scenarios to run for every HC and device.
TESTS="disconnect offline_disconnect offline_online_disconnect"

# How many seconds to wait for system boot.
STARTUP_DELAY="5"

# How many seconds to wait after connecting a device.
CONNECT_DELAY="1"

# How many seconds to wait after disconnecting a device.
DISCONNECT_DELAY="1"

# How many seconds to wait after offline a device.
OFFLINE_DELAY="2"

# Where to look for a QEMU binary.
QEMU_BIN_PATH="../qemu/build/"

# QEMU source repository path (used for QMP access).
QEMU_PATH="../qemu/"

# Where to store test reports (the script will create a tree of subdirectories).
REPORT_PATH="./disconnect_test/"
```

Note that the testing framework requires kernel console extension for HelenOS in
order to access and parse system log.


## Reading the Reports

The report format is simple:

 * "TEST PASS" or "TEST FAILURE"
 * In case of "TEST FAILURE", a line or two might follow, giving details on why
   the test failed, e.g. "Something crashed".
 * Cherry-picked parts of the system log with checkpoints defined by the
   individual scenarios. Note that the cherry-picking mechanism might sometimes
   be off by one line in the beginning and the end of the log.


## Author

This test was created by Petr Mánek. @petrmanek


