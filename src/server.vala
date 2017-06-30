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
using Linux.VirtualTerminal;

[DBus (name = "org.ev3dev.grx.ConsoleRunner")]
public class ConsoleRunnerServer : Object {
    SubprocessLauncher launcher = new SubprocessLauncher (SubprocessFlags.NONE);
    Subprocess? proc;

    public string? tty_name { construct; get; }
    public int vt_num { construct; get; }

    construct {
        tty_name = Posix.ttyname (stdin.fileno ());
        int n;
        tty_name.scanf ("/dev/tty%d", out n);
        vt_num = n;
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
            // clear the environment
            set_environ (launcher, new string[0]);
            // set the passed environment
            env.foreach ((k, v) => {
                launcher.setenv (k, v, true);
            });

            // working directory
            launcher.set_cwd (cwd);

            // setup pipes
            var flags = SubprocessFlags.NONE;
            if (pipe_stdin) {
                flags |= SubprocessFlags.STDIN_PIPE;
            } else {
                flags |= SubprocessFlags.STDIN_INHERIT;
            }
            if (pipe_stdout) {
                flags |= SubprocessFlags.STDOUT_PIPE;
            }
            if (pipe_stderr) {
                flags |= SubprocessFlags.STDERR_PIPE;
            }
            launcher.set_flags (flags);

            proc = launcher.spawnv (args);

            if (pipe_stdin) {
                proc.get_stdin_pipe ().splice_async.begin (stdin_stream, OutputStreamSpliceFlags.CLOSE_TARGET,
                    Priority.DEFAULT, null, (o, r) => {
                        try {
                            proc.get_stdin_pipe ().splice_async.end (r);
                        }
                        catch (IOError e) {
                            stderr.printf ("stdin pipe error: %s\n", e.message);
                        }
                    });
            }

            if (pipe_stdout) {
                stdout_stream.splice_async.begin (proc.get_stdout_pipe (), OutputStreamSpliceFlags.NONE,
                    Priority.DEFAULT, null, (o, r) => {
                        try {
                            stdout_stream.splice_async.end (r);
                        }
                        catch (IOError e) {
                            stderr.printf ("stdout pipe error: %s\n", e.message);
                        }
                    });
            }

            if (pipe_stderr) {
                stderr_stream.splice_async.begin (proc.get_stderr_pipe (), OutputStreamSpliceFlags.NONE,
                    Priority.DEFAULT, null, (o, r) => {
                        try {
                            stderr_stream.splice_async.end (r);
                        }
                        catch (IOError e) {
                            stderr.printf ("stderr pipe error: %s\n", e.message);
                        }
                    });
            }

            // try to activate the VT where the server is running
            var old_vt_num = 0;
            if (vt_num > 0) {
                VirtualTerminal.Stat vt_stat;
                var ret = ioctl (stdin.fileno (), VT_GETSTATE, out vt_stat);
                if (ret == -1) {
                    warning ("Failed to get VT state: %s", strerror (errno));
                } else {
                    old_vt_num = vt_stat.v_active;
                }
                ret = ioctl (stdin.fileno (), VT_ACTIVATE, vt_num);
                if (ret == -1) {
                    warning ("Failed to activate VT: %s", strerror (errno));
                }
                ret = ioctl (stdin.fileno (), VT_WAITACTIVE, vt_num);
                if (ret == -1 && errno == Posix.EINTR) {
                    // this ioctl can be interrupted because if a console is
                    // in graphics mode, it uses signals to negotiate switching
                    // so retry once if intertupted
                    ret = ioctl (stdin.fileno (), VT_WAITACTIVE, vt_num);
                }
                if (ret == -1) {
                    warning ("Failed to wait for active VT: %s", strerror (errno));
                }
            }

            proc.wait_async.begin (null, (o, r) => {
                // if this is the active VT, try to restore the old VT
                if (old_vt_num > 0) {
                    VirtualTerminal.Stat vt_stat;
                    var ret = ioctl (stdin.fileno (), VT_GETSTATE, out vt_stat);
                    if (ret == -1) {
                        warning ("Failed to get VT state: %s", strerror (errno));
                    } else if (vt_stat.v_active == vt_num) {
                        ret = ioctl (stdin.fileno (), VT_ACTIVATE, old_vt_num);
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
        conn.register_object (console_runner_server_object_path, new ConsoleRunnerServer ());
    } catch (IOError e) {
        stderr.printf ("Could not register server\n");
        Process.exit (1);
    }
}

static void on_name_lost (DBusConnection? conn, string name) {
    stderr.printf ("Could not acquire system bus name '%s'\n", name);
    Process.exit (1);
}

static int main (string[] args) {
    Environment.set_prgname (Path.get_basename (args[0]));

    if (Posix.getuid () == 0) {
        stderr.printf ("Refusing to run as root\n");
        return 1;
    }

    Bus.own_name (BusType.SYSTEM, console_runner_server_bus_name, BusNameOwnerFlags.NONE,
        on_bus_aquired, null, on_name_lost);

    new MainLoop ().run ();

    return 0;
}
