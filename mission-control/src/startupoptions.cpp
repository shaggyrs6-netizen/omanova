#include "startupoptions.h"
#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
StartupOptions::StartupOptions(QObject*p):QObject(p){
 timeout.setSingleShot(true);timeout.setInterval(55000);
 connect(&timeout,&QTimer::timeout,this,[this]{process.kill();m_message="Startup check timed out; inspect before retrying";m_available=false;m_restore=false;emit changed();});
 connect(&process,qOverload<int,QProcess::ExitStatus>(&QProcess::finished),this,[this](int code,QProcess::ExitStatus status){timeout.stop();m_busy=false;auto raw=process.readAllStandardOutput();auto d=raw.size()<65536?QJsonDocument::fromJson(raw).object():QJsonObject{};
  if(code==0&&status==QProcess::NormalExit&&d.contains("enabled")){m_enabled=d["enabled"].toBool();m_available=d["available"].toBool();m_message=d["message"].toString();bool restore=m_restore&&!m_enabled;m_restore=false;emit changed();if(restore)emit disabledForRestore();}
  else{m_available=false;m_restore=false;m_message=d["error"].toString("Startup change unavailable; normal desktop remains recoverable");emit changed();}});
 connect(&process,&QProcess::errorOccurred,this,[this](QProcess::ProcessError){m_busy=false;m_available=false;m_restore=false;m_message="Unable to run startup control";emit changed();});refresh();
}
void StartupOptions::run(QString action){if(m_busy)return;m_busy=true;emit changed();process.setProgram(QCoreApplication::applicationDirPath()+"/../bin/wallpaper");process.setArguments({"startup",action});process.start();timeout.start();}
void StartupOptions::refresh(){run("status");}
void StartupOptions::setEnabled(bool v){run(v?"on":"off");}
void StartupOptions::disableAndRestore(){if(m_busy)return;m_restore=true;run("off");}
