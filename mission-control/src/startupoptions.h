#pragma once
#include <QObject>
#include <QProcess>
#include <QTimer>
class StartupOptions:public QObject {
 Q_OBJECT
 Q_PROPERTY(bool enabled READ enabled NOTIFY changed)
 Q_PROPERTY(bool busy READ busy NOTIFY changed)
 Q_PROPERTY(bool available READ available NOTIFY changed)
 Q_PROPERTY(QString message READ message NOTIFY changed)
public:
 explicit StartupOptions(QObject*parent=nullptr);
 bool enabled()const{return m_enabled;}bool busy()const{return m_busy;}bool available()const{return m_available;}QString message()const{return m_message;}
 Q_INVOKABLE void setEnabled(bool enabled);
 Q_INVOKABLE void refresh();
signals:void changed();void disabledForRestore();
public:Q_INVOKABLE void disableAndRestore();
private:
 void run(QString action);QProcess process;QTimer timeout;bool m_enabled=false,m_busy=false,m_available=false,m_restore=false;QString m_message="Checking login startup…";
};
