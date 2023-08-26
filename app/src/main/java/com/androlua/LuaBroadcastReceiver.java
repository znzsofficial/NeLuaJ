package com.androlua;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class LuaBroadcastReceiver extends BroadcastReceiver {

  private OnReceiveListener mRlt;

  public LuaBroadcastReceiver(OnReceiveListener rlt) {
    mRlt = rlt;
  }

  @Override
  public void onReceive(Context context, Intent intent) {
    // TODO: Implement this method
    mRlt.onReceive(context, intent);
  }

  public interface OnReceiveListener {
    public void onReceive(android.content.Context context, android.content.Intent intent);
  }
}
