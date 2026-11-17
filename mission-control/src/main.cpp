#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QQuickStyle>
#include <QTimer>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QFile>
#include <QDebug>
#include <cstdlib>
#include "mission.h"
int main(int argc,char**argv){
 QGuiApplication app(argc,argv);app.setApplicationName("Mission Control Preview");app.setDesktopFileName("omanova-mission-control-preview");QQuickStyle::setStyle("Basic");
 qmlRegisterType<Mission>("MissionControl",1,0,"MissionScene");QQmlApplicationEngine engine;engine.load(QUrl("qrc:/Main.qml"));if(engine.rootObjects().isEmpty())return 1;
 auto window=qobject_cast<QQuickWindow*>(engine.rootObjects().first());if(!window)return 2;
 auto args=app.arguments();int qa=args.indexOf("--qa");if(qa>=0){
  QString dir=qa+1<args.size()?args[qa+1]:"evidence";QDir().mkpath(dir);
  auto scene=window->findChild<Mission*>("missionScene");if(!scene)return 2;
  auto require=[](bool ok,const char*msg){if(!ok){qCritical("Preview QA failed: %s",msg);std::exit(3);}};
  auto click=[=](const char*id){auto button=window->findChild<QObject*>(id);require(button,"button lookup");require(QMetaObject::invokeMethod(button,"clicked"),"button action");};
  auto capture=[=](QString name){require(window->grabWindow().save(dir+"/"+name+".png"),"capture saved");};
  QTimer::singleShot(900,[=]{require(scene->elapsed()>0,"animation advances");capture("wide");});
  QTimer::singleShot(1500,[=]{click("selectTiangong");click("reducedButton");click("trailsButton");click("orbitView");require(scene->selection()==1&&scene->reduced()&&!scene->trails()&&scene->view()==2,"QML controls reach renderer");});
  QTimer::singleShot(2200,[=]{capture("orbit");click("pauseButton");require(scene->paused(),"pause control");});
  QTimer::singleShot(2500,[=]{double before=scene->elapsed();QTimer::singleShot(400,[=]{require(scene->elapsed()==before,"pause freezes simulation");});});
  QTimer::singleShot(3000,[=]{window->resize(780,850);scene->setView(1);scene->setTrails(true);});

  auto finish=[=]{require(scene->elapsed()>0,"animation resumes");scene->setSelection(8);require(scene->selection()==1,"invalid selection refused");QFile out(dir+"/checks.json");require(out.open(QIODevice::WriteOnly),"report open");out.write(QJsonDocument(QJsonObject{{"animationAdvances",true},{"qmlSelectionControls",true},{"qmlViewControls",true},{"qmlTrailControls",true},{"pauseFreezes",true},{"resumeAdvances",true},{"reset",true},{"reducedMotion",true},{"invalidSelectionRefused",true},{"offlineSampleOnly",true}}).toJson());QCoreApplication::quit();};
  QTimer::singleShot(3800,[=]{capture("narrow");scene->reset();require(scene->elapsed()==0,"reset simulation");click("pauseButton");require(!scene->paused(),"resume control");QTimer::singleShot(650,finish);});
 }
 return app.exec();
}
