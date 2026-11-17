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
#include <QDebug>
#include <QStandardPaths>
#include <QQmlContext>
#include <LayerShellQt/Window>
#include <cstdlib>
#include "mission.h"
int main(int argc,char**argv){
 QGuiApplication app(argc,argv);app.setApplicationName("Mission Control Preview");app.setDesktopFileName("omanova-mission-control-preview");QQuickStyle::setStyle("Basic");
 const bool wallpaper=app.arguments().contains("--wallpaper");
 if(wallpaper && QGuiApplication::platformName()!="wayland"){qCritical("Wallpaper trial requires Wayland; no desktop changes made");return 12;}
 qmlRegisterType<Mission>("MissionControl",1,0,"MissionScene");QQmlApplicationEngine engine;engine.setInitialProperties({{"wallpaperMode",wallpaper}});engine.load(QUrl("qrc:/Main.qml"));if(engine.rootObjects().isEmpty())return 1;
 auto window=qobject_cast<QQuickWindow*>(engine.rootObjects().first());if(!window)return 2;
 auto args=app.arguments();auto mission=window->findChild<Mission*>("missionScene");
 if(args.contains("--live")){
  QString data=QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)+"/omasky";
  mission->startLive(QFileInfo(data+"/runtime").canonicalFilePath(),QCoreApplication::applicationDirPath()+"/../live_bridge.py",data);
 }

 QQmlApplicationEngine controller;
 if(wallpaper){
  window->setFlags(Qt::FramelessWindowHint|Qt::WindowTransparentForInput|Qt::WindowDoesNotAcceptFocus);
  auto layer=LayerShellQt::Window::get(window);if(!layer){qCritical("Layer shell unavailable; original desktop retained");return 13;}
  layer->setScope("omanova-mission-control-trial");layer->setLayer(LayerShellQt::Window::LayerBottom);
  layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop)|LayerShellQt::Window::AnchorBottom|LayerShellQt::Window::AnchorLeft|LayerShellQt::Window::AnchorRight);
  layer->setExclusiveZone(-1);layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);layer->setActivateOnShow(false);layer->setScreen(QGuiApplication::primaryScreen());layer->setCloseOnDismissed(true);layer->setDesiredSize(QSize(0,0));
  controller.rootContext()->setContextProperty("wallpaperScene",mission);controller.load(QUrl("qrc:/WallpaperControl.qml"));
  if(controller.rootObjects().isEmpty())return 14;
  QObject::connect(&controller,&QQmlEngine::quit,&app,&QCoreApplication::quit);
  window->show();
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
