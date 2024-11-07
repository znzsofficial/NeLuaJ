package com.androlua

import android.content.Context
import android.content.DialogInterface
import android.graphics.drawable.Drawable
import android.view.View
import android.widget.AdapterView
import android.widget.AdapterView.OnItemLongClickListener
import android.widget.Button
import android.widget.ListAdapter
import android.widget.ListView
import androidx.appcompat.app.AlertDialog
import com.androlua.adapter.ArrayListAdapter

// import android.app.AlertDialog;
/** Created by Administrator on 2017/02/04 0004.  */
class LuaDialog : AlertDialog, DialogInterface.OnClickListener {
    private var mContext: Context
    private var mListView: ListView
    var message: String? = null
        private set
    private var mTitle: String? = null
    var view: View? = null
        private set
    private var mOnClickListener: OnClickListener? = null

    constructor(context: Context) : super(context) {
        mContext = context
        mListView = ListView(mContext)
    }

    constructor(context: Context, theme: Int) : super(context, theme) {
        mContext = context
        mListView = ListView(mContext)
    }

    fun setButton(text: CharSequence?) {
        setOkButton(text)
    }

    fun setButton1(text: CharSequence?) {
        setButton(BUTTON_POSITIVE, text, this)
    }

    fun setButton2(text: CharSequence?) {
        setButton(BUTTON_NEGATIVE, text, this)
    }

    fun setButton3(text: CharSequence?) {
        setButton(BUTTON_NEUTRAL, text, this)
    }

    fun setPosButton(text: CharSequence?) {
        setButton(BUTTON_POSITIVE, text, this)
    }

    fun setNegButton(text: CharSequence?) {
        setButton(BUTTON_NEGATIVE, text, this)
    }

    fun setNeuButton(text: CharSequence?) {
        setButton(BUTTON_NEUTRAL, text, this)
    }

    fun setOkButton(text: CharSequence?) {
        setButton(BUTTON_POSITIVE, text, this)
    }

    fun setCancelButton(text: CharSequence?) {
        setButton(BUTTON_NEGATIVE, text, this)
    }

    fun setOnClickListener(listener: OnClickListener?) {
        mOnClickListener = listener
    }

    fun setPositiveButton(text: CharSequence?, listener: DialogInterface.OnClickListener?) {
        setButton(BUTTON_POSITIVE, text, listener)
    }

    fun setNegativeButton(text: CharSequence?, listener: DialogInterface.OnClickListener?) {
        setButton(BUTTON_NEGATIVE, text, listener)
    }

    fun setNeutralButton(text: CharSequence?, listener: DialogInterface.OnClickListener?) {
        setButton(BUTTON_NEUTRAL, text, listener)
    }

    fun getTitle(): String? {
        return mTitle
    }

    override fun setTitle(title: CharSequence?) {
        // TODO: Implement this method
        mTitle = title.toString()
        super.setTitle(title)
    }

    override fun setMessage(message: CharSequence) {
        // TODO: Implement this method
        this.message = message.toString()
        super.setMessage(message)
    }

    override fun setIcon(icon: Drawable) {
        // TODO: Implement this method
        super.setIcon(icon)
    }

    override fun setView(view: View) {
        // TODO: Implement this method
        this.view = view
        super.setView(view)
    }

    fun setItems(items: Array<String?>) {
        val alist = ArrayList(listOf(*items))
        val adp: ArrayListAdapter<*> =
            ArrayListAdapter(mContext, android.R.layout.simple_list_item_1, alist)
        setAdapter(adp)
        mListView.choiceMode = ListView.CHOICE_MODE_NONE
    }

    fun setAdapter(adp: ListAdapter?) {
        if (mListView != view) setView(mListView)
        mListView.adapter = adp
    }

    fun setSingleChoiceItems(items: Array<CharSequence?>) {
        setSingleChoiceItems(items, 0)
    }

    fun setSingleChoiceItems(items: Array<CharSequence?>, checkedItem: Int) {
        val alist = ArrayList(listOf(*items))
        val adp: ArrayListAdapter<*> = ArrayListAdapter(
            mContext, android.R.layout.simple_list_item_single_choice, alist
        )
        setAdapter(adp)
        mListView.choiceMode = ListView.CHOICE_MODE_SINGLE
        mListView.setItemChecked(checkedItem, true)
    }

    fun setMultiChoiceItems(items: Array<CharSequence?>) {
        setMultiChoiceItems(items, IntArray(0))
    }

    fun setMultiChoiceItems(items: Array<CharSequence?>, checkedItems: IntArray) {
        val alist = ArrayList(listOf(*items))
        val adp: ArrayListAdapter<*> = ArrayListAdapter(
            mContext, android.R.layout.simple_list_item_multiple_choice, alist
        )
        setAdapter(adp)
        mListView.choiceMode = ListView.CHOICE_MODE_MULTIPLE
        for (i in checkedItems) mListView.setItemChecked(i, true)
    }

    override fun getListView(): ListView {
        return mListView
    }

    fun setOnItemClickListener(listener: AdapterView.OnItemClickListener?) {
        mListView.onItemClickListener = listener
    }

    fun setOnItemLongClickListener(listener: OnItemLongClickListener?) {
        mListView.onItemLongClickListener = listener
    }

    fun setOnItemSelectedListener(listener: AdapterView.OnItemSelectedListener?) {
        mListView.onItemSelectedListener = listener
    }

    override fun setOnCancelListener(listener: DialogInterface.OnCancelListener?) {
        // TODO: Implement this method
        super.setOnCancelListener(listener)
    }

    override fun setOnDismissListener(listener: DialogInterface.OnDismissListener?) {
        // TODO: Implement this method
        super.setOnDismissListener(listener)
    }

//    override fun show() {
//        super.show()
//    }
//
//    override fun hide() {
//        super.hide()
//    }
//
//    override fun isShowing(): Boolean {
//        return super.isShowing()
//    }

    override fun onClick(dialog: DialogInterface, which: Int) {
        if (mOnClickListener != null) mOnClickListener!!.onClick(this, getButton(which))
    }

    interface OnClickListener {
        fun onClick(dlg: LuaDialog?, btn: Button?)
    } /*
  public void close()
  {
      super.dismiss();
  }

  @Override
  public void dismiss()
  {
      super.hide();
  }*/
}
