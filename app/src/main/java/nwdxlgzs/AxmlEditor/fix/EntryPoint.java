package com.nwdxlgzs.AxmlEditor.fix;

import java.io.File;
import java.io.IOException;
import java.lang.reflect.Field;
import com.nwdxlgzs.AxmlEditor.rt.*;
 
public class EntryPoint {

	 
	public static byte[] fix(byte[] in) throws IOException {
		Reader reader = new Reader(in);
		Writer writer = new Writer();

		try { // write non-utf8 string for all platform
			Field fStringItems = Writer.class.getDeclaredField("stringItems");
			fStringItems.setAccessible(true);
			Object stringItems = fStringItems.get(writer);
			Field fuseUTF8 = stringItems.getClass().getDeclaredField("useUTF8");
			fuseUTF8.setAccessible(true);
			fuseUTF8.setBoolean(stringItems, false);
		} catch (Exception ex) {
			ex.printStackTrace();
		}

		reader.accept(new Visitor(writer) {

			@Override
			public void attr(String ns, String name, int resourceId, int type, Object obj) {
				 
				super.attr(ns, name, resourceId, type, obj);
			}

			@Override
			public NodeVisitor child(String ns, String name) {// manifest
				NodeVisitor nv = super.child(ns, name);
				return new NodeVisitor(nv) {

					@Override
					public void attr(String ns, String name, int resourceId, int type, Object obj) {
						// System.out.println(String.format("ns:%s, name:%s, resourceId:%d-%s, type:%d-%s, obj:%s",
						// ns,
						// name, resourceId, Integer.toHexString(resourceId),
						// type, Integer.toHexString(type),
						// obj.toString()));
						String realName = (-1 == resourceId || AxmlNameHelper.get(resourceId)==null) ? name : AxmlNameHelper.get(resourceId).getName();
						String realNs = null == ns ? null : AxmlNameHelper.ns;

						// System.out.println(String.format("ns:%s, name:%s, resourceId:%d-%s, type:%d-%s, obj:%s",
						// ns,
						// realName, resourceId,
						// Integer.toHexString(resourceId), type,
						// Integer.toHexString(type),
						// obj.toString()));
						super.attr(realNs, realName, resourceId, type, obj);
						// super.attr(ns, name, resourceId, type, obj);
					}

					@Override
					public NodeVisitor child(String ns, String name) {// application
						if (name.equals("uses-sdk") || name.equals("uses-permission")) {
							// 修复uses-sdk、uses-permission标签的属性。
							return new NodeVisitor(super.child(ns, name)) {

								public void attr(String ns, String name, int resourceId, int type, Object obj) {
									String realName = (-1 == resourceId || AxmlNameHelper.get(resourceId)==null) ? name : AxmlNameHelper.get(resourceId).getName();
									String realNs = null == ns ? null : AxmlNameHelper.ns;
									super.attr(realNs, realName, resourceId, type, obj);
								}
							};
						} else if (name.equals("application")) {
							// 修复application标签的属性。
							return new NodeVisitor(super.child(ns, name)) {

								public void attr(String ns, String name, int resourceId, int type, Object obj) {
									String realName = (-1 == resourceId || AxmlNameHelper.get(resourceId)==null) ? name : AxmlNameHelper.get(resourceId).getName();
									String realNs = null == ns ? null : AxmlNameHelper.ns;
									super.attr(realNs, realName, resourceId, type, obj);
								}

								@Override
								public NodeVisitor child(String ns, String name) {
									if (name.equals("activity") || name.equals("service") || name.equals("receiver")
											|| name.equals("provider")) {
										// 修复activity、service、receiver标签的属性。
										return new NodeVisitor(super.child(ns, name)) {
											@Override
											public void attr(String ns, String name, int resourceId, int type,
													Object obj) {
												String realName = (-1 == resourceId || AxmlNameHelper.get(resourceId)==null) ? name : AxmlNameHelper.get(resourceId).getName();
												String realNs = null == ns ? null : AxmlNameHelper.ns;
												super.attr(realNs, realName, resourceId, type, obj);
											}

											public NodeVisitor child(String ns, String name) {
												if (name.equals("intent-filter") || name.equals("meta-data")) {
													// 修复intent-filter、meta-data标签的属性。
													return new NodeVisitor(super.child(ns, name)) {
														public void attr(String ns, String name, int resourceId,
																int type, Object obj) {
															String realName = (-1 == resourceId || AxmlNameHelper.get(resourceId)==null) ? name : AxmlNameHelper.get(resourceId).getName();
															String realNs = null == ns ? null : AxmlNameHelper.ns;
															super.attr(realNs, realName, resourceId, type, obj);
														}
													};
												}
												return super.child(ns, name);
											}
										};
									}
									return super.child(ns, name);
								}
							};
						}
						return super.child(ns, name);
					}
				};
			}
		});

		return writer.toByteArray();
	}

}
