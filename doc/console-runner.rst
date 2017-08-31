==============
console-runner
==============

:Author: David Lechner
:Date: August 2017


NAME
====

console-runner - D-Bus client/server to run programs on a remote virtual console.


SYNOPSIS
========

**conrun-server**

**conrun** [**--directory=***dir*] [**--pipe-stdin**] [**--pipe-stdout**] [**--pipe-stderr**] [**--**] *command* [*arg* ...]]

**conrun-kill** [**--signal=***signal*]


DESCRIPTION
===========

**console-runner** is a set of programs that provides a similar function to
**openvt**. The main difference is that it allows you to launch programs from
remote terminals (e.g. SSH shell) without needing root privileges. It
accomplishes this by having a separate "server" program that is launched on the
target virtual terminal so that the user already has ownership of a virtual
terminal. Then commands can be sent from anywhere (locally, via D-Bus) and run
on a virtual terminal. This is mostly useful for starting graphics programs
that require a virtual terminal rather than running in a desktop environment.

**Note:** **console-runner** requires some manual configuration before the
first use. See the `D-BUS`_ section below.


OPTIONS
=======

**conrun-server** has no options.

**conrun** options
------------------

*command*
    The command to run remotely on **conrun-server**.

*arg* ...
    Additional arguments for *command*.

**-d**, **--directory=***dir*
    Specifies the working directory for the remote command. When omitted, the
    current working directory of the **conrun** command is used.

**-i**, **--pipe-stdin**
    Pipe the standard input from **conrun** to *command*. When omitted, *command*
    inherits the standard input of **conrun-server**.

**-o**, **--pipe-stdout**
    Pipe the standard output from *command* to **conrun**. When omitted, *command*
    inherits the standard output of **conrun-server**.

**-e**, **--pipe-stderr**
    Pipe the standard error from *command* to **conrun**.. When omitted, *command*
    inherits the standard error of **conrun-server**.

**-h**, **--help**
    Print a help message and exit.

**-v**, **--version**
    Print the program version and exit.

**--**
    Separates *command* from other options. It is only needed when any *arg*
    contains flags starting with ``-``.


**conrun-kill** options
-----------------------

**-s**, **--signal=***signal*
    Specifies the signal to be sent. The signal can be a posix signal name
    (with or without the "SIG" prefix) or the signal number. The default is
    to use `SIGTERM` when this option is omitted.

**-h**, **--help**
    Print a help message and exit.

**-v**, **--version**
    Print the program version and exit.


ENVIRONMENT
===========

**conrun** sends the current environment to **conrun-server** so that *command*
executes using the environment of **conrun** rather than **conrun-server**.
This also includes the current working directory in addition to environment
variables.


D-BUS
=====

**console-runner** uses the system bus because it is normally used in situations
where there is no session for the user. Because of this, you must create a
configuration file to give users permission to use **console-runner**.

Here is an example::

    <!DOCTYPE busconfig PUBLIC
        "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
        "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">

    <busconfig>
        <policy user="myname">
            <allow own="org.ev3dev.ConsoleRunner"/>
            <allow send_type="method_call"/>
        </policy>
    </busconfig>

Replace ``myname`` with your user name and save the file as
``/etc/dbus-1/system.d/org.ev3dev.ConsoleRunner.conf``. Then you will be
able to use **console-runner** with your user account.


AUTOMATION
==========

Here is an example systemd service that will essentially automatically log in
and run **conrun-server** using your user account::

    [Unit]
    Description=Console runner for myname

    [Service]
    Type=simple
    ExecStartPre=+/bin/chown myname /dev/%i
    ExecStart=/usr/bin/conrun-server
    ExecStopPost=+/bin/chown root /dev/%i
    User=myname
    StandardInput=tty-fail
    StandardOutput=tty
    StandardError=journal
    TTYPath=/dev/%i

    [Install]
    WantedBy=multi-user.target

Replace ``myname`` with your user name and save this as
``/etc/systemd/system/console-run@.service``. Then, as root, run::

    systemctl daemon-reload
    systemctl enable console-run@tty5.service
    systemctl start console-run@tty5.service

This will start **conrun-server** on ``tty5`` and also make is so that it starts
automatically at boot.
