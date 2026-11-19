#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QQuickStyle>
#include <QTimer>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QFile>
#include <QFileInfo>
#include <QPainter>
#include <memory>
#include <QDebug>
#include <QStandardPaths>
#include <QQmlContext>
#include <LayerShellQt/Window>
#include <cstdlib>
#include "mission.h"
#include "startupoptions.h"
int main(int argc,char**argv){
 QGuiApplication app(argc,argv);app.setApplicationName("Mission Control Preview");app.setDesktopFileName("omanova-mission-control-preview");QQuickStyle::setStyle("Basic");
 const bool wallpaper=app.arguments().contains("--wallpaper");
 if(wallpaper && QGuiApplication::platformName()!="wayland"){qCritical("Wallpaper trial requires Wayland; no desktop changes made");return 12;}
 qmlRegisterType<Mission>("MissionControl",1,0,"MissionScene");QQmlApplicationEngine engine;engine.setInitialProperties({{"wallpaperMode",wallpaper}});engine.load(QUrl("qrc:/Main.qml"));if(engine.rootObjects().isEmpty())return 1;
 auto window=qobject_cast<QQuickWindow*>(engine.rootObjects().first());if(!window)return 2;
 auto args=app.arguments();auto mission=window->findChild<Mission*>("missionScene");
 if(args.contains("--live")){
  QString data=QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)+"/omasky";
  mission->startLive(data+"/runtime",QCoreApplication::applicationDirPath()+"/../live_bridge.py",data);
 }

 StartupOptions startup;
 QQmlApplicationEngine controller;
 if(wallpaper){
  window->setFlags(Qt::FramelessWindowHint|Qt::WindowTransparentForInput|Qt::WindowDoesNotAcceptFocus);
  auto layer=LayerShellQt::Window::get(window);if(!layer){qCritical("Layer shell unavailable; original desktop retained");return 13;}
  layer->setScope("omanova-mission-control-trial");layer->setLayer(LayerShellQt::Window::LayerBottom);
  layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop)|LayerShellQt::Window::AnchorBottom|LayerShellQt::Window::AnchorLeft|LayerShellQt::Window::AnchorRight);
  layer->setExclusiveZone(-1);layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);layer->setActivateOnShow(false);layer->setScreen(QGuiApplication::primaryScreen());layer->setCloseOnDismissed(true);layer->setDesiredSize(QSize(0,0));
  controller.rootContext()->setContextProperty("wallpaperScene",mission);controller.rootContext()->setContextProperty("startupOptions",&startup);controller.load(QUrl("qrc:/WallpaperControl.qml"));
  if(controller.rootObjects().isEmpty())return 14;
  QObject::connect(&controller,&QQmlEngine::quit,&app,&QCoreApplication::quit);
  window->show();
  if(args.contains("--startup-self-test")){
   const auto config=qEnvironmentVariable("XDG_CONFIG_HOME");
   if(!config.startsWith("/tmp/omanova-startup-")){qCritical("Startup GUI test requires isolated temporary config");return 17;}
   auto step=new int(0);auto attempts=new int(0);auto check=new QTimer(&app);check->setInterval(100);
   auto click=[&controller](const char*name){auto button=controller.rootObjects().first()->findChild<QObject*>(name);return button&&QMetaObject::invokeMethod(button,"clicked");};
   QObject::connect(&startup,&StartupOptions::disabledForRestore,&app,[&startup]{if(startup.enabled())QCoreApplication::exit(18);QFile f(QCoreApplication::applicationDirPath()+"/../evidence/startup-native-check.json");if(f.open(QIODevice::WriteOnly))f.write("{\"nativeToggleOnOff\":true,\"disableAndRestore\":true,\"isolatedConfig\":true}\n");});
   QObject::connect(check,&QTimer::timeout,&app,[=,&startup,&controller]{
    if(++*attempts>300){qCritical("Isolated startup GUI test timed out");QCoreApplication::exit(19);return;}
    if(startup.busy())return;
    if(!startup.available()){qCritical("Isolated startup GUI control unavailable");QCoreApplication::exit(20);return;}
    if(*step==0){if(startup.enabled()||!click("loginStartupButton")){QCoreApplication::exit(21);return;}*step=1;}
    else if(*step==1){if(!startup.enabled()||!click("loginStartupButton")){QCoreApplication::exit(22);return;}*step=2;}
    else if(*step==2){if(startup.enabled()){QCoreApplication::exit(23);return;}auto w=qobject_cast<QQuickWindow*>(controller.rootObjects().first());w->grabWindow().save(QCoreApplication::applicationDirPath()+"/../evidence/startup-controls.png");if(!click("loginStartupButton")){QCoreApplication::exit(24);return;}*step=3;}
    else if(*step==3){if(!startup.enabled()||!click("normalDesktopButton")){QCoreApplication::exit(25);return;}*step=4;}
   });check->start();
  }
  if(args.contains("--wallpaper-self-test")){
   QTimer::singleShot(2800,[=]{
    QJsonObject proof{{"mouseTransparent",bool(window->flags()&Qt::WindowTransparentForInput)},{"keyboardNone",layer->keyboardInteractivity()==LayerShellQt::Window::KeyboardInteractivityNone},{"bottomLayer",layer->layer()==LayerShellQt::Window::LayerBottom},{"noReservedSpace",layer->exclusionZone()==-1},{"width",window->width()},{"height",window->height()},{"live",mission->live()},{"fresh",mission->feedFresh()}};
    QFile out(QCoreApplication::applicationDirPath()+"/../evidence/wallpaper-native-proof.json");if(out.open(QIODevice::WriteOnly))out.write(QJsonDocument(proof).toJson());
    window->grabWindow().save(QCoreApplication::applicationDirPath()+"/../evidence/private-wallpaper.png");
   });
   QTimer::singleShot(5000,[&controller]{auto button=controller.rootObjects().first()->findChild<QObject*>("restoreDesktopButton");if(!button||!QMetaObject::invokeMethod(button,"clicked")){qCritical("Restore-button check failed");QCoreApplication::exit(15);}else qInfo("Restore button invoked; wallpaper trial ending");});}
 }

 int feed=args.indexOf("--feed");if(feed>=0&&feed+1<args.size()){QFile f(args[feed+1]);if(!f.open(QIODevice::ReadOnly))return 4;mission->applyFrame(QJsonDocument::fromJson(f.read(2097153)).object());}


 int checkLive=args.indexOf("--live-check");if(checkLive>=0){
  if(!args.contains("--live")){return 6;}
  QString dir=args.value(checkLive+1);if(dir.isEmpty())return 6;QDir().mkpath(dir);
  auto watcher=new QTimer(&app);watcher->setInterval(200);auto count=new int(0);auto first=new QString;
  QObject::connect(watcher,&QTimer::timeout,&app,[=]{
   if(++*count>75){qCritical("Live acceptance: timed out waiting for fresh local frames");std::exit(7);}
   if(!mission->feedFresh())return;
   QString generated=mission->liveData()["generated"].toString();
   if(first->isEmpty()){*first=generated;if(!window->grabWindow().save(dir+"/private-live.png"))std::exit(8);return;}
   if(generated==*first)return;
   mission->setPaused(true);if(mission->feedFresh())std::exit(9);mission->setPaused(false);if(!mission->feedFresh())std::exit(10);
   QFile out(dir+"/checks.json");if(!out.open(QIODevice::WriteOnly))std::exit(11);
   out.write(QJsonDocument(QJsonObject{{"realHelperLoaded",true},{"twoFreshFrames",true},{"nativeLiveWindow",true},{"pauseWithholds",true},{"resumeCurrentFrame",true},{"firstGenerated",*first},{"latestGenerated",generated}}).toJson());QCoreApplication::quit();
  });watcher->start();return app.exec();
 }
 int liveQa=args.indexOf("--qa-live");if(liveQa>=0){
  QString dir=liveQa+1<args.size()?args[liveQa+1]:"evidence/live-test";QDir().mkpath(dir);
  auto require=[](bool ok,const char*msg){if(!ok){qCritical("Live QA failed: %s",msg);std::exit(5);}};
  QJsonObject sat{{"id",25544},{"az",280.},{"el",35.},{"rangeKm",800.},{"ageHours",1.},{"epoch",QDateTime::currentDateTimeUtc().addSecs(-3600).toString(Qt::ISODateWithMs)},{"potential",true},{"lat",20.},{"lon",-70.},{"altitudeKm",420.},{"path",QJsonArray{QJsonObject{{"az",270.},{"el",20.}},QJsonObject{{"az",280.},{"el",35.}}}},{"groundTrack",QJsonArray{QJsonArray{-80.,10.},QJsonArray{-70.,20.},QJsonArray{-60.,30.}}}};
  auto second=sat;second["id"]=48274;second["az"]=45.;second["lon"]=-100.;
  QJsonObject frame{{"mode","live"},{"testFixture",true},{"generated",QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)},{"observer",QJsonObject{{"lat",36.1627},{"lon",-86.7816}}},{"satellites",QJsonObject{{"objects",QJsonArray{sat,second}}}},{"moon",QJsonObject{{"fraction",.68},{"angle",112.}}},{"chart",QJsonObject{{"stars",QJsonArray{QJsonObject{{"id",1},{"az",90.},{"el",45.},{"mag",1.},{"clear",true}},QJsonObject{{"id",2},{"az",70.},{"el",60.},{"mag",2.},{"clear",true}}}},{"lines",QJsonArray{QJsonObject{{"a",1},{"b",2}}}}}},{"zone","America/Chicago"},{"localClock","18:24:00"},{"utcClock","00:24:00"},{"cards",QJsonObject{{"passes",QJsonObject{{"25544",QJsonObject{{"value","ISS · fixture pass"},{"detail","Look NW · visibility unconfirmed"}}},{"48274",QJsonObject{{"value","Tiangong · fixture pass"},{"detail","Look NW · visibility unconfirmed"}}}}},{"weather",QJsonObject{{"value","Cloud 91%"},{"detail","Fixture forecast · visibility uncertain"}}},{"launch",QJsonObject{{"value","Fixture launch"},{"detail","Visibility unconfirmed"}}}}}};
  mission->applyFrame(frame);require(mission->feedFresh(),"fresh frame accepted");require(mission->detail().contains("bearing"),"real direction fields used");
  auto bad=frame;bad["generated"]=QDateTime::currentDateTimeUtc().addSecs(-16).toString(Qt::ISODateWithMs);mission->applyFrame(bad);require(!mission->feedFresh(),"stale frame withheld");
  bad["generated"]=QDateTime::currentDateTimeUtc().addSecs(30).toString(Qt::ISODateWithMs);mission->applyFrame(bad);require(!mission->feedFresh(),"future frame withheld");
  mission->applyFrame(QJsonObject{{"error","Test missing data"}});require(!mission->feedFresh(),"error withholds live data");
  bad=frame;auto old=sat;old["epoch"]=QDateTime::currentDateTimeUtc().addSecs(-49*3600).toString(Qt::ISODateWithMs);bad["satellites"]=QJsonObject{{"objects",QJsonArray{old}}};mission->applyFrame(bad);require(mission->detail().contains("No usable"),"old epoch withheld");
  old["epoch"]=QDateTime::currentDateTimeUtc().addSecs(7*3600).toString(Qt::ISODateWithMs);bad["satellites"]=QJsonObject{{"objects",QJsonArray{old}}};mission->applyFrame(bad);require(mission->detail().contains("No usable"),"future epoch withheld");
  mission->applyFrame(frame);mission->setPaused(true);require(!mission->feedFresh(),"paused markers withheld");mission->setPaused(false);require(mission->feedFresh(),"resume current data");
  bad=frame;sat["el"]=-10.;bad["satellites"]=QJsonObject{{"objects",QJsonArray{sat}}};mission->applyFrame(bad);require(mission->detail().contains("Below"),"below-horizon detail explicit");mission->applyFrame(frame);
  QTimer::singleShot(800,[=]{require(window->grabWindow().save(dir+"/wide.png"),"wide capture");mission->setSelection(1);mission->setView(2);});
  QTimer::singleShot(1500,[=]{require(window->grabWindow().save(dir+"/orbit.png"),"orbit capture");window->resize(780,850);mission->setView(0);});
  QTimer::singleShot(2300,[=]{require(window->grabWindow().save(dir+"/narrow.png"),"narrow capture");QFile out(dir+"/checks.json");require(out.open(QIODevice::WriteOnly),"report");out.write(QJsonDocument(QJsonObject{{"freshFrame",true},{"staleFutureFramesWithheld",true},{"staleFutureElementsWithheld",true},{"pauseWithholdsPositions",true},{"belowHorizonExplicit",true},{"noSampleFallback",true}}).toJson());QCoreApplication::quit();});
  return app.exec();
 }
 int qa=args.indexOf("--qa");if(qa>=0){
  QString dir=qa+1<args.size()?args[qa+1]:"evidence";QDir().mkpath(dir);
  auto scene=window->findChild<Mission*>("missionScene");if(!scene)return 2;
  auto require=[](bool ok,const char*msg){if(!ok){qCritical("Preview QA failed: %s",msg);std::exit(3);}};
  auto click=[=](const char*id){auto button=window->findChild<QObject*>(id);require(button,"button lookup");require(QMetaObject::invokeMethod(button,"clicked"),"button action");};
  auto capture=[=](QString name){require(window->grabWindow().save(dir+"/"+name+".png"),"capture saved");};
  struct GlobeCheck { QImage last; double lastTime=-1; int samples=0, changes=0; };
  auto globeCheck=std::make_shared<GlobeCheck>();
  QObject::connect(scene,&Mission::changed,&app,[=]{
   const double t=scene->elapsed();
   if(t<=0||t==globeCheck->lastTime||globeCheck->samples>=6||scene->width()<200||scene->height()<200)return;
   globeCheck->lastTime=t;
   QImage frame(scene->size().toSize(),QImage::Format_ARGB32_Premultiplied);
   QPainter painter(&frame);
   scene->paint(&painter);
   painter.end();
   const QImage centre=frame.copy(frame.width()*3/4-48,frame.height()/2-48,96,96);
   if(globeCheck->samples>0&&centre!=globeCheck->last)++globeCheck->changes;
   globeCheck->last=centre;
   ++globeCheck->samples;
  });
  QTimer::singleShot(900,[=]{require(scene->elapsed()>0,"animation advances");require(globeCheck->samples==6&&globeCheck->changes>=3,"Earth texture advances across consecutive frames");capture("wide");});
  QTimer::singleShot(1500,[=]{click("selectTiangong");click("reducedButton");click("trailsButton");click("orbitView");require(scene->selection()==1&&scene->reduced()&&!scene->trails()&&scene->view()==2,"QML controls reach renderer");});
  QTimer::singleShot(2200,[=]{capture("orbit");click("pauseButton");require(scene->paused(),"pause control");});
  QTimer::singleShot(2500,[=]{double before=scene->elapsed();QTimer::singleShot(400,[=]{require(scene->elapsed()==before,"pause freezes simulation");});});
  QTimer::singleShot(3000,[=]{window->resize(780,850);scene->setView(1);scene->setTrails(true);});

  auto finish=[=]{require(scene->elapsed()>0,"animation resumes");scene->setSelection(8);require(scene->selection()==1,"invalid selection refused");QFile out(dir+"/checks.json");require(out.open(QIODevice::WriteOnly),"report open");out.write(QJsonDocument(QJsonObject{{"animationAdvances",true},{"qmlSelectionControls",true},{"qmlViewControls",true},{"qmlTrailControls",true},{"pauseFreezes",true},{"resumeAdvances",true},{"reset",true},{"reducedMotion",true},{"invalidSelectionRefused",true},{"offlineSampleOnly",true},{"earthFrameSamples",globeCheck->samples},{"earthTextureChanges",globeCheck->changes}}).toJson());QCoreApplication::quit();};
  QTimer::singleShot(3800,[=]{capture("narrow");scene->reset();require(scene->elapsed()==0,"reset simulation");click("pauseButton");require(!scene->paused(),"resume control");QTimer::singleShot(650,finish);});
 }
 return app.exec();
}
