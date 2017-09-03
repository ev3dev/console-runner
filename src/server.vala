/*
 * server.vala
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

using Linux;
using Linux.Console;
using Linux.VirtualTerminal;

[DBus (name = "org.ev3dev.ConsoleRunner")]
public class ConsoleRunnerServer : Object {
    Subprocess? proc;
    Mode vt_mode;
    int kbd_mode;
    Posix.termios termios;

    public string? tty_name { get; private set; }
    public int vt_num { get; private set; }

    public ConsoleRunnerServer() throws Error {
        if (!Posix.isatty (Posix.STDIN_FILENO)) {
            throw new IOError.FAILED ("Not a tty");
        }
        tty_name = Posix.ttyname (Posix.STDIN_FILENO);
        if (tty_name == null) {
            throw Fixes.GLib.IOError.from_errno (errno, "Failed to get tty name");
        }
        int n;
        var count = tty_name.scanf ("/dev/tty%d", out n);
        if (count == 1) {
            vt_num = n;
            // save original state for later
            ioctl (Posix.STDIN_FILENO, VT_GETMODE, out vt_mode);
            ioctl (Posix.STDIN_FILENO, KDGKBMODE, out kbd_mode);
            Posix.tcgetattr (Posix.STDIN_FILENO, out termios);
        }
    }

    void reset_tty () {
        // escape sequence to reset the terminal
        Posix.write (Posix.STDIN_FILENO, "\033c", 3);
    }

    // work around broken vapi
    [CCode (cname = "g_subprocess_launcher_set_environ")]
    static extern void set_environ (SubprocessLauncher launcher, [CCode (array_length = 1.1)]string[] env);

    public void start (string[] args, HashTable<string, string> env, string cwd,
            bool pipe_stdin, UnixInputStream stdin_stream,
            bool pipe_stdout, UnixOutputStream stdout_stream,
            bool pipe_stderr, UnixOutputStream stderr_stream) throws ConsoleRunnerError {
        if (proc != null) {
            throw new ConsoleRunnerError.BUSY ("Process is running");
        }
        if (args == null) {
            throw new ConsoleRunnerError.INVALID_ARGUMENT ("args cannot be null");
        }
        if (args.length == 0) {
            throw new ConsoleRunnerError.INVALID_ARGUMENT ("args cannot be empty");
        }
        if (args[0] == null) {
            throw new ConsoleRunnerError.INVALID_ARGUMENT ("first arg cannot be null");
        }
        if (args[0] == "") {
            throw new ConsoleRunnerError.INVALID_ARGUMENT ("first arg cannot be empty");
        }
        try {
            var launcher = new SubprocessLauncher (SubprocessFlags.NONE);

            // clear the environment
            set_environ (launcher, new string[0]);
            // set the passed environment
            env.foreach ((k, v) => {
                launcher.setenv (k, v, true);
            });

            // working directory
            launcher.set_cwd (cwd);

            // setup pipes
            if (pipe_stdin) {
                launcher.take_stdin_fd (stdin_stream.get_fd ());
            }
            else {
                launcher.set_flags (SubprocessFlags.STDIN_INHERIT);
            }
            if (pipe_stdout) {
                launcher.take_stdout_fd (stdout_stream.get_fd ());
            }
            if (pipe_stderr) {
                launcher.take_stderr_fd (stderr_stream.get_fd ());
            }

            reset_tty ();

            proc = launcher.spawnv (args);

            // try to activate the VT where the server is running
            var old_vt_num = 0;
            if (vt_num > 0) {
                VirtualTerminal.Stat vt_stat;
                var ret = ioctl (Posix.STDIN_FILENO, VT_GETSTATE, out vt_stat);
                if (ret == -1) {
                    warning ("Failed to get VT state: %s", strerror (errno));
                } else {
                    old_vt_num = vt_stat.v_active;
                }
                ret = ioctl (Posix.STDIN_FILENO, VT_ACTIVATE, vt_num);
                if (ret == -1) {
                    warning ("Failed to activate VT: %s", strerror (errno));
                }
                ret = ioctl (Posix.STDIN_FILENO, VT_WAITACTIVE, vt_num);
                if (ret == -1 && errno == Posix.EINTR) {
                    // this ioctl can be interrupted because if a console is
                    // in graphics mode, it uses signals to negotiate switching
                    // so retry once if intertupted
                    ret = ioctl (Posix.STDIN_FILENO, VT_WAITACTIVE, vt_num);
                }
                if (ret == -1) {
                    warning ("Failed to wait for active VT: %s", strerror (errno));
                }
            }

            proc.wait_async.begin (null, (o, r) => {
                if (vt_num > 0) {
                    // make sure the process does not leave us stuck in graphics
                    // mode or without keyboard input
                    ioctl (Posix.STDIN_FILENO, KDSETMODE, TerminalMode.TEXT);
                    ioctl (Posix.STDIN_FILENO, VT_SETMODE, vt_mode);
                    ioctl (Posix.STDIN_FILENO, KDSKBMODE, kbd_mode);
                    Posix.tcsetattr (Posix.STDIN_FILENO, Posix.TCSAFLUSH, termios);
                }

                // if this is the active VT, try to restore the old VT
                if (old_vt_num > 0) {
                    VirtualTerminal.Stat vt_stat;
                    var ret = ioctl (Posix.STDIN_FILENO, VT_GETSTATE, out vt_stat);
                    if (ret == -1) {
                        warning ("Failed to get VT state: %s", strerror (errno));
                    } else if (vt_stat.v_active == vt_num) {
                        ret = ioctl (Posix.STDIN_FILENO, VT_ACTIVATE, old_vt_num);
                        if (ret == -1) {
                            warning ("Failed to activate old VT: %s", strerror (errno));
                        }
                    }
                }

                try {
                    proc.wait_async.end (r);
                    if (proc.get_if_exited ()) {
                        exited (proc.get_exit_status ());
                    }
                    else if (proc.get_if_signaled ()) {
                        signaled (proc.get_term_sig ());
                    }
                    else {
                        throw new IOError.FAILED ("Unhandled process exit!");
                    }
                }
                catch (Error e) {
                    errored (e.message);
                }
                proc = null;
            });
        }
        catch (Error e) {
            throw new ConsoleRunnerError.FAILED (e.message);
        }
    }

    public void signal (int sig) throws ConsoleRunnerError {
        if (proc == null) {
            throw new ConsoleRunnerError.FAILED ("Process is not running");
        }
        proc.send_signal (sig);
    }

    public signal void exited (int code);

    public signal void signaled (int sig);

    public signal void errored (string message);
}

static void on_bus_aquired (DBusConnection conn) {
    try {
        conn.register_object (console_runner_server_object_path, server);
    }
    catch (IOError e) {
        stderr.printf ("Could not register server\n");
        Process.exit (1);
    }
}

static void on_name_lost (DBusConnection? conn, string name) {
    stderr.printf ("Could not acquire system bus name '%s'\n", name);
    Process.exit (1);
}

static ConsoleRunnerServer server;

static int main (string[] args) {
    Environment.set_prgname (Path.get_basename (args[0]));

    if (Posix.getuid () == 0) {
        stderr.printf ("Refusing to run as root\n");
        return 1;
    }

    try {
        server = new ConsoleRunnerServer ();
    }
    catch (Error err) {
        stderr.printf ("%s\n", err.message);
        Process.exit (1);
    }

    Bus.own_name (BusType.SYSTEM, console_runner_server_bus_name, BusNameOwnerFlags.NONE,
        on_bus_aquired, null, on_name_lost);

    new MainLoop ().run ();

    return 0;
}
