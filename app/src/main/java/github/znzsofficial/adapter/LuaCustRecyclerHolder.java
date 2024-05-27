package github.znzsofficial.adapter;

import android.view.View;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

public class LuaCustRecyclerHolder extends RecyclerView.ViewHolder {
    public LuaCustRecyclerHolder(@NonNull View itemView) {
        super(itemView);
    }

    public Object Tag = null;

    public void setViews(Object tag) {
        Tag = tag;
    }

    public Object getViews() {
        return Tag;
    }
}
