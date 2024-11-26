package com.androlua

import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.IOException
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.Socket

/**
 * Created by Administrator on 2017/10/20 0020.
 */
class LuaClient : LuaGcable {
    private var mOnReadLineListener: OnReadLineListener? = null
    private var mSocket: Socket? = null
    private var `in`: BufferedReader? = null
    private var out: BufferedWriter? = null
    private var mGc = false

    constructor(context: LuaContext) {
        context.regGc(this)
    }

    constructor()

    fun start(dstName: String?, dstPort: Int): Boolean {
        if (mSocket != null) return false

        try {
            mSocket = Socket(dstName, dstPort)
            `in` = BufferedReader(InputStreamReader(mSocket!!.inputStream))
            out = BufferedWriter(OutputStreamWriter(mSocket!!.outputStream))
            SocketThread(mSocket!!).start()
            return true
        } catch (e: IOException) {
            e.printStackTrace()
            return false
        }
    }

    fun stop(): Boolean {
        if (mSocket == null) return false
        try {
            mSocket!!.close()
            return true
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }

    fun setOnReadLineListener(listener: OnReadLineListener?) {
        mOnReadLineListener = listener
    }

    override fun gc() {
        stop()
        mGc = true
    }

    override fun isGc(): Boolean {
        return mGc
    }

    fun write(text: String?): Boolean {
        try {
            out!!.write(text)
            return true
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }

    fun flush(): Boolean {
        try {
            out!!.flush()
            return true
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }

    fun newLine(): Boolean {
        try {
            out!!.newLine()
            out!!.flush()
            return true
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }

    inner class SocketThread(private val mSocket: Socket) : Thread() {
        override fun run() {
            try {
                var line: String?
                while ((`in`!!.readLine().also { line = it }) != null) {
                    if (mOnReadLineListener != null) mOnReadLineListener!!.onReadLine(
                        this@LuaClient,
                        this,
                        line
                    )
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        fun write(text: String): Boolean {
            try {
                out!!.write(text)
                return true
            } catch (e: Exception) {
                e.printStackTrace()
                return false
            }
        }

        fun flush(): Boolean {
            try {
                out!!.flush()
                return true
            } catch (e: Exception) {
                e.printStackTrace()
                return false
            }
        }

        fun newLine(): Boolean {
            try {
                out!!.newLine()
                out!!.flush()
                return true
            } catch (e: Exception) {
                e.printStackTrace()
                return false
            }
        }

        fun close(): Boolean {
            try {
                mSocket.close()
                return true
            } catch (e: Exception) {
                e.printStackTrace()
                return false
            }
        }
    }

    interface OnReadLineListener {
        fun onReadLine(server: LuaClient?, socket: SocketThread?, line: String?)
    }
}
