package it.a11y.blindensport.webadmin.ui;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/** A view only admins holding at least one of these permissions may open (checked by {@link AccessGuard}). */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.TYPE)
public @interface RequiresPermission {
    String[] value();
}
