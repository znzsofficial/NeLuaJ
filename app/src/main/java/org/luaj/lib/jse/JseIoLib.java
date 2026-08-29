package org.luaj.lib.jse;

import org.luaj.LuaError;
import org.luaj.LuaString;
import org.luaj.lib.IoLib;

import java.io.BufferedInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PrintStream;
import java.io.RandomAccessFile;

/**
 * JSE implementation of Lua's io library.
 */
public class JseIoLib extends IoLib {
    private static final int STDOUT = 1;
    private static final int STDERR = 2;

    @Override
    protected File a(String filename, boolean readMode, boolean appendMode, boolean updateMode, boolean binaryMode) {
        try {
            RandomAccessFile file = new RandomAccessFile(filename, readMode ? "r" : "rw");
            if (appendMode) {
                file.seek(file.length());
            } else if (!readMode) {
                file.setLength(0);
            }
            return new FileImpl(file, null, null, null);
        } catch (IOException exception) {
            throw new LuaError(exception);
        }
    }

    @Override
    protected File b(String program, String mode) {
        if ("rw".equals(mode)) {
            throw new LuaError("io.popen mode 'rw' is not supported; use a process API with separate asynchronous streams");
        }
        try {
            Process process = Runtime.getRuntime().exec(program);
            drainErrorStream(process);
            if ("w".equals(mode)) {
                drainStream(process.getInputStream(), "luaj-popen-stdout");
                return new FileImpl(null, null, process.getOutputStream(), process);
            }
            return new FileImpl(null, process.getInputStream(), null, process);
        } catch (IOException exception) {
            throw new LuaError(exception);
        }
    }

    /**
     * A child blocks when its stderr pipe fills, even when Lua only reads stdout. Keep stderr
     * drained because io.popen has no separate stderr channel to expose.
     */
    private static void drainErrorStream(Process process) {
        drainStream(process.getErrorStream(), "luaj-popen-stderr");
    }

    private static void drainStream(InputStream stream, String name) {
        Thread drainer = new Thread(() -> {
            try (InputStream input = stream) {
                byte[] buffer = new byte[8_192];
                while (input.read(buffer) != -1) {
                    // Discard an unexposed process stream so it cannot fill its pipe capacity.
                }
            } catch (IOException ignored) {
                // Closing a popen handle closes this stream while the drainer may still be reading.
            }
        }, name);
        drainer.setDaemon(true);
        drainer.start();
    }

    @Override
    protected File d() {
        try {
            java.io.File temporaryFile = java.io.File.createTempFile(".luaj", ".tmp");
            temporaryFile.deleteOnExit();
            return new FileImpl(new RandomAccessFile(temporaryFile, "rw"), null, null, null);
        } catch (IOException exception) {
            throw new LuaError(exception);
        }
    }

    @Override
    protected File e() {
        return new StdoutFile(STDERR);
    }

    @Override
    protected File f() {
        return new StdinFile();
    }

    @Override
    protected File g() {
        return new StdoutFile(STDOUT);
    }

    private static LuaError ioError(IOException exception) {
        return new LuaError(exception);
    }

    private final class FileImpl extends File {
        private final RandomAccessFile file;
        private final InputStream input;
        private final OutputStream output;
        private final Process process;
        private boolean closed;
        private boolean noBuffer;

        private FileImpl(RandomAccessFile file, InputStream input, OutputStream output, Process process) {
            this.file = file;
            this.input = input == null || input.markSupported() ? input : new BufferedInputStream(input);
            this.output = output;
            this.process = process;
        }

        @Override
        public void close() {
            if (closed) {
                return;
            }
            closed = true;

            IOException failure = null;
            failure = close(file, failure);
            failure = close(input, failure);
            failure = close(output, failure);
            if (process != null) {
                failure = close(process.getErrorStream(), failure);
                process.destroy();
            }
            if (failure != null) {
                throw ioError(failure);
            }
        }

        @Override
        public void flush() {
            if (output == null) {
                return;
            }
            try {
                output.flush();
            } catch (IOException exception) {
                throw ioError(exception);
            }
        }

        @Override
        public void write(LuaString value) {
            try {
                if (output != null) {
                    output.write(value.c, value.d, value.e);
                    if (noBuffer) {
                        output.flush();
                    }
                    return;
                }
                if (file != null) {
                    file.write(value.c, value.d, value.e);
                    return;
                }
                throw new LuaError("not implemented");
            } catch (IOException exception) {
                throw ioError(exception);
            }
        }

        @Override
        public boolean isclosed() {
            return closed;
        }

        @Override
        public boolean isstdfile() {
            // Process-backed handles also have no RandomAccessFile, but must remain closable.
            return false;
        }

        @Override
        public int seek(String option, int position) {
            if (file == null) {
                throw new LuaError("not implemented");
            }
            try {
                if ("set".equals(option)) {
                    file.seek(position);
                } else if ("end".equals(option)) {
                    file.seek(file.length() + position);
                } else {
                    file.seek(file.getFilePointer() + position);
                }
                return (int) file.getFilePointer();
            } catch (IOException exception) {
                throw ioError(exception);
            }
        }

        @Override
        public void setvbuf(String mode, int size) {
            noBuffer = "no".equals(mode);
        }

        @Override
        public int remaining() {
            if (file == null) {
                return -1;
            }
            try {
                return (int) (file.length() - file.getFilePointer());
            } catch (IOException exception) {
                throw ioError(exception);
            }
        }

        @Override
        public int peek() {
            try {
                if (input != null) {
                    input.mark(1);
                    int value = input.read();
                    input.reset();
                    return value;
                }
                if (file != null) {
                    long position = file.getFilePointer();
                    int value = file.read();
                    file.seek(position);
                    return value;
                }
                throw new LuaError("not implemented");
            } catch (IOException exception) {
                throw ioError(exception);
            }
        }

        @Override
        public int read() {
            try {
                if (input != null) {
                    return input.read();
                }
                if (file != null) {
                    return file.read();
                }
                throw new LuaError("not implemented");
            } catch (IOException exception) {
                throw ioError(exception);
            }
        }

        @Override
        public int read(byte[] bytes, int offset, int length) {
            try {
                if (file != null) {
                    return file.read(bytes, offset, length);
                }
                if (input != null) {
                    return input.read(bytes, offset, length);
                }
                throw new LuaError("not implemented");
            } catch (IOException exception) {
                throw ioError(exception);
            }
        }

        @Override
        public String tojstring() {
            return "file (" + (closed ? "closed" : hashCode()) + ')';
        }

        private IOException close(java.io.Closeable closeable, IOException failure) {
            if (closeable == null) {
                return failure;
            }
            try {
                closeable.close();
            } catch (IOException exception) {
                if (failure == null) {
                    return exception;
                }
                failure.addSuppressed(exception);
            }
            return failure;
        }
    }

    private final class StdoutFile extends File {
        private final int type;

        private StdoutFile(int type) {
            this.type = type;
        }

        @Override
        public void close() {
            // Standard streams belong to the process, not Lua's io library.
        }

        @Override
        public void flush() {
            stream().flush();
        }

        @Override
        public void write(LuaString value) {
            stream().write(value.c, value.d, value.e);
        }

        @Override
        public boolean isclosed() {
            return false;
        }

        @Override
        public boolean isstdfile() {
            return true;
        }

        @Override
        public int seek(String option, int position) {
            return 0;
        }

        @Override
        public void setvbuf(String mode, int size) {
        }

        @Override
        public int remaining() {
            return 0;
        }

        @Override
        public int peek() {
            return 0;
        }

        @Override
        public int read() {
            return 0;
        }

        @Override
        public int read(byte[] bytes, int offset, int length) {
            return 0;
        }

        @Override
        public String tojstring() {
            return "file (" + hashCode() + ')';
        }

        private PrintStream stream() {
            return type == STDERR ? o.l : o.k;
        }
    }

    private final class StdinFile extends File {
        @Override
        public void close() {
            // Standard streams belong to the process, not Lua's io library.
        }

        @Override
        public void flush() {
        }

        @Override
        public void write(LuaString value) {
        }

        @Override
        public boolean isclosed() {
            return false;
        }

        @Override
        public boolean isstdfile() {
            return true;
        }

        @Override
        public int seek(String option, int position) {
            return 0;
        }

        @Override
        public void setvbuf(String mode, int size) {
        }

        @Override
        public int remaining() {
            return -1;
        }

        @Override
        public int peek() {
            try {
                o.j.mark(1);
                int value = o.j.read();
                o.j.reset();
                return value;
            } catch (IOException exception) {
                throw ioError(exception);
            }
        }

        @Override
        public int read() {
            try {
                return o.j.read();
            } catch (IOException exception) {
                throw ioError(exception);
            }
        }

        @Override
        public int read(byte[] bytes, int offset, int length) {
            try {
                return o.j.read(bytes, offset, length);
            } catch (IOException exception) {
                throw ioError(exception);
            }
        }

        @Override
        public String tojstring() {
            return "file (" + hashCode() + ')';
        }
    }
}
