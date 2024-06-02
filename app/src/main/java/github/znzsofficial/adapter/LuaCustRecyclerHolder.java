package github.znzsofficial.adapter;

import android.view.View;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import org.luaj.LuaTable;

public class LuaCustRecyclerHolder extends RecyclerView.ViewHolder {
    public LuaCustRecyclerHolder(@NonNull View itemView) {
        super(itemView);
    }

    public LuaTable Tag = null;

    public void setViews(LuaTable tag) {
        Tag = tag;
    }

    public LuaTable getViews() {
        return Tag;
    }
}
