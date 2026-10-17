package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.component.dependency.StyleSheet;
import com.vaadin.flow.component.page.AppShellConfigurator;
import com.vaadin.flow.component.page.Meta;
import com.vaadin.flow.theme.lumo.Lumo;

@StyleSheet(Lumo.STYLESHEET)
@StyleSheet("styles.css")
@Meta(name = "color-scheme", content = "light dark")
public class AppShell implements AppShellConfigurator {
}
