/*
 * common.vala
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

const string console_runner_server_bus_name = "org.ev3dev.ConsoleRunner";
const string console_runner_server_object_path = "/org/ev3dev/ConsoleRunner/Server";

[DBus (name = "org.ev3dev.ConsoleRunner")]
public interface ConsoleRunner : Object {
    public abstract void start (string[] args, HashTable<string, string> env, string cwd,
        bool pipe_stdin, UnixInputStream stdin_stream,
        bool pipe_stdout, UnixOutputStream stdout_stream,
        bool pipe_stderr, UnixOutputStream stderr_stream) throws DBusError, ConsoleRunnerError;
    public abstract void signal (int sig) throws DBusError, ConsoleRunnerError;
    public signal void exited (int code);
    public signal void signaled (int code);
    public signal void errored (string msg);
}

[DBus (name = "org.ev3dev.ConsoleRunner.Error")]
public errordomain ConsoleRunnerError
{
    FAILED,
    INVALID_ARGUMENT,
    BUSY
}
