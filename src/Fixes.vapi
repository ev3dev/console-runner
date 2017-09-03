/* Fixes.vapi - additional bindings/fixes */

namespace Fixes.GLib.IOError {
    /**
     * Replacement for GLib.IOError.from_errno (int).
     *
     * There is a bug in the vala compiler that tries to assign the return value
     * as GError* instead of int. This function returns and int like it should.
     * https://bugzilla.gnome.org/show_bug.cgi?id=664530
     */
    [CCode (cheader_filename = "gio/gio.h", cname = "g_io_error_from_errno")]
    int g_io_error_from_errno (int errno);

    [CCode (cheader_filename = "glib.h", cname = "g_prefix_error")]
    void g_prefix_error (global::GLib.Error **error, string format, ...);

    public global::GLib.IOError from_errno (int errno, string? prefix = null) {
        var code = g_io_error_from_errno (errno);
        var message = global::GLib.strerror (errno);
        var err = new global::GLib.Error (global::GLib.IOError.quark (), code, message);
        if (prefix != null) {
            g_prefix_error (&err, prefix);
        }
        return (global::GLib.IOError)err;
    }
}
