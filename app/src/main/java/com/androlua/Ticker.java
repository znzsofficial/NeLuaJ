package com.androlua;


import android.os.Handler;

public final class Ticker {
    private long mPeriod = 1000;
    private boolean mEnabled = true;
    private boolean isRun = false;
    private long mLast;
    private long mOffset;
    private Ticker.OnTickListener mOnTickListener;

    private final Handler mHandler;

    private final Thread mThread;

    public Ticker() {
        mHandler = new Handler((message) -> {
            if (mOnTickListener != null)
                mOnTickListener.onTick();
            return false;
        });
        mThread = new Thread(() -> {
            isRun = true;
            while (isRun) {
                long now = System.currentTimeMillis();
                if (!mEnabled)
                    mLast = now - mOffset;
                if (now - mLast >= mPeriod) {
                    mLast = now;
                    mHandler.sendEmptyMessage(0);
                }
                try {
                    Thread.sleep(1);
                } catch (InterruptedException ignored) {
                }
            }
        });
    }

    public void setPeriod(long period) {
        mLast = System.currentTimeMillis();
        mPeriod = period;
    }

    public long getPeriod() {
        return mPeriod;
    }


    public void setInterval(long period) {
        mLast = System.currentTimeMillis();
        mPeriod = period;
    }

    public long getInterval() {
        return mPeriod;
    }

    public void setEnabled(boolean enabled) {
        mEnabled = enabled;
        if (!enabled)
            mOffset = System.currentTimeMillis() - mLast;
    }

    public boolean getEnabled() {
        return mEnabled;
    }

    public void setOnTickListener(OnTickListener ltr) {
        mOnTickListener = ltr;
    }

    public void start() {
        mThread.start();
    }

    public void stop() {
        isRun = false;
    }

    public boolean isRun() {
        return isRun;
    }

    public interface OnTickListener {
        void onTick();
    }
}
