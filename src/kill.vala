/*
 * kill.vala
 *
 * Copyright (c) 2017 David Lechner <david@lechnology.com>
 * This file is part of console-runner.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

static int exitCode = 1;
static ConsoleRunner client;
static MainLoop loop;
static KillSignal kill_signal;

static string? signal_arg = null;
static bool version = false;

const OptionEntry[] options = {
    { "signal", 's', 0, OptionArg.STRING, ref signal_arg, "The signal name or number (default=TERM)", "SIGNAL" },
    { "version", 'v', 0, OptionArg.NONE, ref version, "Display version number and exit", null },
    { null }
};

const string extra_parameters = "<signal>";
const string summary = "Sends a signal to a remote process running via console-runner-server.";

enum KillSignal {
    ABRT = Posix.SIGABRT,
    ALRM = Posix.SIGALRM,
    BUS = Posix.SIGBUS,
    CHLD = Posix.SIGCHLD,
    CONT = Posix.SIGCONT,
    FPE = Posix.SIGFPE,
    HUP = Posix.SIGHUP,
    ILL = Posix.SIGILL,
    INT = Posix.SIGINT,
    KILL = Posix.SIGKILL,
    PIPE = Posix.SIGPIPE,
    QUIT = Posix.SIGQUIT,
    SEGV = Posix.SIGSEGV,
    STOP = Posix.SIGSTOP,
    TERM = Posix.SIGTERM,
    TSTP = Posix.SIGTSTP,
    TTIN = Posix.SIGTTIN,
    TTOU = Posix.SIGTTOU,
    USR1 = Posix.SIGUSR1,
    USR2 = Posix.SIGUSR2,
    POLL = Posix.SIGPOLL,
    PROF = Posix.SIGPROF,
    SYS = Posix.SIGSYS,
    TRAP = Posix.SIGTRAP,
    URG = Posix.SIGURG,
    VTALRM = Posix.SIGVTALRM,
    XCPU = Posix.SIGXCPU,
    XFSZ = Posix.SIGXFSZ,
    IOT = Posix.SIGIOT,
    STKFLT  = Posix.SIGSTKFLT,
}

static void on_bus_name_appeared (DBusConnection connection, string name, string name_owner) {
    try {
        client = Bus.get_proxy_sync<ConsoleRunner> (BusType.SYSTEM, name,
            console_runner_server_object_path,
            DBusProxyFlags.DO_NOT_AUTO_START);

        client.signal (kill_signal);
    }
    catch (Error e) {
        if (e is DBusError.SERVICE_UNKNOWN) {
            stderr.printf ("console-runner-service is not running\n");
        }
        else if (e is ConsoleRunnerError.FAILED) {
            DBusError.strip_remote_error (e);
            stderr.printf ("Sending signal failed: %s\n", e.message);
        }
        else {
            stderr.printf ("Unexpected error: %s\n", e.message);
        }
    }
    loop.quit ();
}

static void on_bus_name_vanished (DBusConnection connection, string name) {
    // we lost the d-bus connection, or there wasn't one to begin with
    stderr.printf ("console-runner-service is not running\n");
    loop.quit ();
}

static int main (string[] args) {
    Environment.set_prgname (Path.get_basename (args[0]));

    try {
        var context = new OptionContext (extra_parameters);
        context.set_help_enabled (true);
        context.set_summary (summary);
        context.add_main_entries (options, null);
        context.parse (ref args);
    }
    catch (OptionError e) {
        stderr.printf ("Error: %s\n", e.message);
        stdout.printf ("Run '%s --help' to see a full list of available command line options.\n", args[0]);
        return 1;
    }

    if (version) {
        stdout.printf ("%s: v%s\n", Environment.get_prgname (), console_runner_version);
        return 0;
    }

    if (signal_arg == null) {
        signal_arg = "TERM";
    }

    // Try to match the signal name to an enum value. Enum nicks are lower
    // case posix signal names (without the sig prefix).
    var signal_name = signal_arg.down ();
    if (signal_name.has_prefix ("sig")) {
        signal_name = signal_name.substring (3);
    }
    var enum_class = (EnumClass)typeof(KillSignal).class_ref ();
    var enum_value = enum_class.get_value_by_nick (signal_name);
    if (enum_value == null) {
        kill_signal = (KillSignal)int.parse (signal_arg);
    }
    else {
        kill_signal = (KillSignal)enum_value.value;
    }

    if (kill_signal == (KillSignal)0) {
        stderr.printf ("Error: unknown signal: %s\n", signal_arg);
        return 1;
    }

    var watch_id = Bus.watch_name (BusType.SYSTEM, console_runner_server_bus_name,
        BusNameWatcherFlags.NONE, on_bus_name_appeared, on_bus_name_vanished);

    loop = new MainLoop ();
    loop.run();

    Bus.unwatch_name (watch_id);

    return exitCode;
}
