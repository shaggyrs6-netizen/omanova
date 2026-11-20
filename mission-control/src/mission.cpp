#include "mission.h"
#include <QPainter>
#include <QPainterPath>
#include <QRandomGenerator>
#include <QMouseEvent>
#include <QQuickWindow>
#include <QtMath>
#include <algorithm>
#include <cmath>
#include <limits>
#include <QJsonArray>
#include <QJsonDocument>
#include <QFileInfo>
#include <QFile>
#include <QDir>
#include <QProcessEnvironment>
#include <QFontMetricsF>
namespace {
constexpr int globeSize = 600;
constexpr int motionIntervalMs = 33;
constexpr int reducedIntervalMs = 67;
}

static const QColor cyan("#5de7ef"),white("#edf5fa"),muted("#90aabd"),amber("#f9bb64");
static QString name(int i){return i==0?"ISS":"TIANGONG";}
static void label(QPainter*p,QPointF pos,QString text,int size,QColor color=white){QFont f("DejaVu Sans");f.setPixelSize(size);p->setFont(f);p->setPen(color);p->drawText(pos,text);}
static void diamond(QPainter*p,QPointF pos,QColor color,bool selected){
 if(selected){QRadialGradient glow(pos,22);glow.setColorAt(0,QColor(75,230,245,100));glow.setColorAt(1,Qt::transparent);p->setBrush(glow);p->setPen(Qt::NoPen);p->drawEllipse(pos,22,22);}
 QPolygonF poly;poly<<pos+QPointF(0,-6)<<pos+QPointF(6,0)<<pos+QPointF(0,6)<<pos+QPointF(-6,0);p->setPen(QPen(color,1.5));p->setBrush(selected?color:QColor("#081726"));p->drawPolygon(poly);
}
Mission::Mission(QQuickItem*p):QQuickPaintedItem(p){
 setAntialiasing(true);setAcceptedMouseButtons(Qt::LeftButton);texture.load(":/assets/earth.jpg");texture=texture.convertToFormat(QImage::Format_RGB32);prepareGlobe();
 QRandomGenerator rng(4261);for(int i=0;i<650;i++){stars<<QPointF(rng.generateDouble(),rng.generateDouble());sizes<<(.4+rng.generateDouble()*1.25);}
 connect(this, &QQuickItem::windowChanged, this, [this](QQuickWindow *window) {
  if (!window) return;
  connect(window, &QWindow::visibilityChanged, this, [this](QWindow::Visibility visibility) {
   syncAnimationTimer();
   if (m_live && !m_paused && visibility != QWindow::Minimized && visibility != QWindow::Hidden)
    QTimer::singleShot(0, this, &Mission::poll);
  });
  syncAnimationTimer();
 });
 connect(this, &QQuickItem::visibleChanged, this, &Mission::syncAnimationTimer);
 timer.setTimerType(Qt::PreciseTimer);
 connect(&timer, &QTimer::timeout, this, [this] {
  const double maxDelta = qMax(.15, timer.interval() * .002);
  m_elapsed += qMin(clock.restart() / 1000., maxDelta) * (m_reduced ? .12 : 1.);
  emit changed();
  update();
 });
 syncAnimationTimer();
}

void Mission::syncAnimationTimer() {
 const auto visibility = window() ? window()->visibility() : QWindow::Hidden;
 if (m_paused || m_wallpaperRate == 0 || !isVisible() ||
     visibility == QWindow::Hidden || visibility == QWindow::Minimized) {
  timer.stop();
  return;
 }
 int interval = m_reduced ? reducedIntervalMs : motionIntervalMs;
 if (m_wallpaperRate > 0)
  interval = qMax(interval, qRound(1000. / m_wallpaperRate));
 if (timer.isActive() && timer.interval() == interval) return;
 clock.restart();
 timer.start(interval);
}

void Mission::configureWallpaperPower(const QString &config, const QString &supplies) {
 powerConfig = config;
 powerSupplies = supplies;
 connect(&powerTimer, &QTimer::timeout, this, &Mission::refreshWallpaperPower, Qt::UniqueConnection);
 refreshWallpaperPower();
 powerTimer.start(2000);
}

void Mission::refreshWallpaperPower() {
 QFile file(powerConfig);
 QJsonObject options;
 if (file.open(QIODevice::ReadOnly) && file.size() <= 4096)
  options = QJsonDocument::fromJson(file.read(4096)).object();
 int frameRate = options["frameRate"].toInt(30);
 int batteryRate = options["batteryRate"].toInt(5);
 if (frameRate != 0 && frameRate != 5 && frameRate != 15 && frameRate != 30) frameRate = 30;
 if (batteryRate != -1 && batteryRate != 0 && batteryRate != 5) batteryRate = 5;

 const auto readSupply = [](const QDir &supply, const QString &field) {
  QFile entry(supply.filePath(field));
  return entry.open(QIODevice::ReadOnly) ? entry.read(64).trimmed() : QByteArray{};
 };
 const QDir directory(powerSupplies);
 bool onBattery = false;
 for (const QString &name : directory.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
  const QDir supply(directory.filePath(name));
  if (readSupply(supply, "type") == "Battery" && readSupply(supply, "scope") != "Device" &&
      readSupply(supply, "status") == "Discharging") {
   onBattery = true;
   break;
  }
 }
 // Battery mode is a ceiling. A user-selected Still or slower rate stays in effect.
 const int effectiveRate = onBattery && batteryRate >= 0 ? qMin(frameRate, batteryRate) : frameRate;
 if (effectiveRate == m_wallpaperRate) return;
 m_wallpaperRate = effectiveRate;
 syncAnimationTimer();
}

void Mission::setPaused(bool paused) {
 if (paused == m_paused) return;
 m_paused = paused;
 syncAnimationTimer();
 if (!paused && m_live) QTimer::singleShot(0, this, &Mission::poll);
 emit changed();
 update();
}

void Mission::setReduced(bool reduced) {
 m_reduced = reduced;
 syncAnimationTimer();
 emit changed();
 update();
}
void Mission::setTrails(bool v){m_trails=v;emit changed();update();}
void Mission::setSelection(int v){if(v<0||v>1)return;m_selection=v;emit changed();update();}
void Mission::setView(int v){if(v<0||v>2)return;m_view=v;emit changed();update();}
void Mission::reset(){m_elapsed=0;emit changed();update();}
QString Mission::detail()const{if(m_live){if(!feedFresh())return feedStatus();auto r=liveStation(m_selection);if(r.isEmpty())return name(m_selection)+" · No usable cached elements";double km=r["rangeKm"].toDouble();bool miles=frame["miles"].toBool();return name(m_selection)+QString(" / %1° bearing / %2° up / %3 %4 / elements %5 h old / ").arg(r["az"].toDouble(),0,'f',1).arg(r["el"].toDouble(),0,'f',1).arg(km/(miles?1.609344:1.),0,'f',0).arg(miles?"mi":"km").arg(r["ageHours"].toDouble(),0,'f',1)+(r["el"].toDouble()<0?"Below your horizon":r["potential"].toBool()?"Potential geometry; visibility unconfirmed":"Visibility uncertain");}return name(m_selection)+"  /  "+QString::number(238+int(m_elapsed*.7+m_selection*104)%100)+"° bearing  /  "+QString::number(32+int(m_elapsed*.4+m_selection*13)%27)+"° up  /  SAMPLE";}
QPointF Mission::satellite(int i,double t,const QRectF&r)const{
 double a=t*.027+i*2.3-1.7;double radius=r.width()*.5;return r.center()+QPointF(sin(a)*radius*.79,-cos(a*.77)*radius*.58);
}
void Mission::drawSky(QPainter*p,QRectF area){
 if(m_live){drawLiveSky(p,area);return;}
 const double r=qMax(25.,qMin(area.width()*.5-38,area.height()*.5-38));QRectF disc(area.center().x()-r,area.center().y()-r,2*r,2*r);skyRect=disc;
 QRadialGradient bg(disc.center(),r);bg.setColorAt(0,QColor("#0c2437"));bg.setColorAt(1,QColor("#030d1c"));p->setBrush(bg);p->setPen(QPen(QColor("#235368"),1));p->drawEllipse(disc);
 for(int i=1;i<=4;i++){double rr=r*i/4.;p->setBrush(Qt::NoBrush);p->setPen(QPen(QColor(i==4?"#4996a5":"#193d51"),i==4?1.1:.65));p->drawEllipse(disc.center(),rr,rr);}
 for(int a=0;a<360;a+=5){double rad=qDegreesToRadians(double(a));QPointF d(sin(rad),-cos(rad));p->setPen(QPen(QColor(a%30==0?"#7ed4dd":"#2c5d71"),1));p->drawLine(disc.center()+d*(r+3),disc.center()+d*(r+(a%30==0?12:7)));}
 for(int a=0;a<180;a+=30){double rad=qDegreesToRadians(double(a));QPointF d(sin(rad),-cos(rad));p->setPen(QPen(QColor("#163449"),.6,Qt::DashLine));p->drawLine(disc.center()-d*r,disc.center()+d*r);}
 // Deterministic illustrative stars; no real-location or constellation claim.
 p->save();QPainterPath clip;clip.addEllipse(disc.adjusted(3,3,-3,-3));p->setClipPath(clip);
 QVector<QPointF> bright;
 for(int i=0;i<stars.size();i++){QPointF pt=QPointF(disc.left()+stars[i].x()*disc.width(),disc.top()+stars[i].y()*disc.height());double sz=sizes[i];p->setBrush(QColor(183,219,238,150+int(sz*55)));p->setPen(Qt::NoPen);p->drawEllipse(pt,sz*.6,sz*.6);if(i%23==0)bright<<pt;}
 p->setPen(QPen(QColor(91,154,188,75),.8));for(int i=1;i<bright.size();i++)if(QLineF(bright[i],bright[i-1]).length()<r*.65)p->drawLine(bright[i],bright[i-1]);
 for(int i=1;i>=0;i--){QColor c=i==m_selection?cyan:amber;if(m_trails){QPainterPath trail;for(int k=-35;k<=35;k++){QPointF pt=satellite(i,m_elapsed+k*.9,disc);if(k==-35)trail.moveTo(pt);else trail.lineTo(pt);}p->setPen(QPen(QColor(c.red(),c.green(),c.blue(),150),1.25,Qt::DashLine));p->setBrush(Qt::NoBrush);p->drawPath(trail);}QPointF pt=satellite(i,m_elapsed,disc);hits[i]=pt;diamond(p,pt,c,i==m_selection);}
 p->restore();for(int i=0;i<2;i++){QPointF pt=satellite(i,m_elapsed,disc);double x=qMin(pt.x()+13,area.right()-105);label(p,QPointF(x,pt.y()-13),name(i),13,i==m_selection?cyan:amber);}
 label(p,disc.center()+QPointF(-6,-r-20),"N",17);label(p,disc.center()+QPointF(-6,r+29),"S",17);label(p,disc.center()+QPointF(-r-29,6),"W",17);label(p,disc.center()+QPointF(r+18,6),"E",17);
 label(p,disc.center()+QPointF(9,-r*.5-5),"45°",10,muted);
}
void Mission::prepareGlobe()
{
    if (texture.isNull()) return;
    globe = QImage(globeSize, globeSize, QImage::Format_ARGB32_Premultiplied);
    globe.fill(Qt::transparent);
    const double tilt = qDegreesToRadians(20.);
    const double sl = std::sin(tilt), cl = std::cos(tilt);
    const double radius = globeSize * .5 - 1;
    const double centre = (globeSize - 1) * .5;
    globeProjection.reserve(globeSize * globeSize);
    for (int y = 0; y < globeSize; ++y) {
        const double yy = (centre - y) / radius;
        for (int x = 0; x < globeSize; ++x) {
            const double xx = (x - centre) / radius;
            const double q = xx * xx + yy * yy;
            if (q >= 1) continue;
            const double z = std::sqrt(1 - q);
            const double latitude = std::asin(yy * cl + z * sl);
            const double longitude = std::atan2(xx, z * cl - yy * sl);
            const int row = qBound(0, int((.5 - latitude / M_PI) * texture.height()), texture.height() - 1);
            const float column = (longitude / (2 * M_PI) + .5) * texture.width();
            const float light = qBound(.11, (-xx * .65 + yy * .25 + z * .60) * 1.2, 1.05);
            const float rim = std::pow(1 - z, 4);
            globeProjection.append(GlobePixel{y * globeSize + x, row, column, light, rim});
        }
    }
}

void Mission::bakeGlobe()
{
    const double longitude = viewLongitude();
    if (globeProjection.isEmpty() || longitude == paintedLongitude) return;
    const int width = texture.width();
    const float offset = longitude / 360. * width;
    auto *output = reinterpret_cast<QRgb *>(globe.bits());
    for (const auto &pixel : globeProjection) {
        float col = pixel.column + offset;
        if (col < 0) col += width;
        if (col >= width) col -= width;
        const int left = int(col);
        const int right = left + 1 == width ? 0 : left + 1;
        const float fraction = col - left;
        const auto *row = reinterpret_cast<const QRgb *>(texture.constScanLine(pixel.row));
        const QRgb a = row[left], b = row[right];
        auto shade = [&](int low, int high, float glow) {
            return qBound(0, int((low + (high - low) * fraction) * pixel.light + pixel.rim * glow), 255);
        };
        output[pixel.destination] = qRgb(shade(qRed(a), qRed(b), 9),
                                        shade(qGreen(a), qGreen(b), 50),
                                        shade(qBlue(a), qBlue(b), 80));
    }
    paintedLongitude = longitude;
}
void Mission::drawEarth(QPainter*p,QRectF area){
 if(m_live){drawLiveEarth(p,area);return;}
 double r=qMin(area.width(),area.height())*.445;QPointF center=area.center();earthRect=QRectF(center-QPointF(r,r),QSizeF(r*2,r*2));
 QRadialGradient halo(center,r*1.12);halo.setColorAt(0,QColor(20,80,165,0));halo.setColorAt(.86,QColor(25,90,180,0));halo.setColorAt(.90,QColor(48,162,248,95));halo.setColorAt(1,Qt::transparent);p->setPen(Qt::NoPen);p->setBrush(halo);p->drawEllipse(center,r*1.12,r*1.12);
 bakeGlobe();
 p->drawImage(earthRect,globe);
 p->setBrush(Qt::NoBrush);p->setPen(QPen(QColor(91,191,247,145),1.3));p->drawEllipse(earthRect);
 for(int i=1;i>=0;i--){QColor c=i==m_selection?cyan:amber;double phase=m_elapsed*.035+i*2.4;auto point=[&](double a){return center+QPointF(sin(a)*r*1.12,cos(a)*r*.33+sin(a)*r*.38*(i?-.6:1));};
 if(m_trails){for(int k=0;k<180;k++){double a=k*2*M_PI/180,b=(k+1)*2*M_PI/180;p->setPen(QPen(QColor(c.red(),c.green(),c.blue(),cos(a)>0?175:45),1.15,cos(a)>0?Qt::SolidLine:Qt::DashLine));p->drawLine(point(a),point(b));}}
 QPointF pt=point(phase);hits[2+i]=pt;diamond(p,pt,c,i==m_selection);label(p,pt+QPointF(13,-12),name(i),13,c);
 }
}
void Mission::paint(QPainter*p){p->setRenderHint(QPainter::Antialiasing);hits.fill(QPointF(-10000,-10000),4);
 QLinearGradient bg(0,0,width(),height());bg.setColorAt(0,QColor("#040d1c"));bg.setColorAt(.5,QColor("#061729"));bg.setColorAt(1,QColor("#020812"));p->fillRect(boundingRect(),bg);
 QRadialGradient nebula(QPointF(width()*.65,height()*.32),width()*.65);nebula.setColorAt(0,QColor(18,61,102,58));nebula.setColorAt(.45,QColor(10,39,76,20));nebula.setColorAt(1,Qt::transparent);p->fillRect(boundingRect(),nebula);
 for(int i=0;i<stars.size();i++){p->setPen(QColor(137,188,216,i%5==0?115:45));p->drawPoint(QPointF(stars[i].x()*width(),stars[i].y()*height()));}
 bool both=m_view==0;QRectF left=both?QRectF(0,0,width()*.5,height()):boundingRect(),right=both?QRectF(width()*.5,0,width()*.5,height()):boundingRect();
 if(m_view!=2){drawSky(p,left);}
 if(m_view!=1){drawEarth(p,right);}
 if(both){p->setPen(QPen(QColor("#1d5264"),1));
 p->setBrush(Qt::NoBrush);QPainterPath seam;seam.moveTo(width()*.5-24,10);seam.lineTo(width()*.5,34);seam.lineTo(width()*.5,height()-48);seam.lineTo(width()*.5+24,height()-24);p->drawPath(seam);
 int i=m_selection;if(hits[i].x()>0&&hits[2+i].x()>0){p->setPen(QPen(QColor(93,231,239,95),.8));QPainterPath link;link.moveTo(hits[i]);link.lineTo(width()*.5-36,hits[i].y());link.lineTo(width()*.5+12,hits[2+i].y());link.lineTo(hits[2+i]);p->drawPath(link);}}
}
void Mission::mousePressEvent(QMouseEvent*e){for(int i=0;i<hits.size();i++){if((i<2&&m_view==2)||(i>=2&&m_view==1))continue;if(QLineF(e->position(),hits[i]).length()<30){setSelection(i%2);e->accept();return;}}e->ignore();}

Mission::~Mission(){if(helper.state()!=QProcess::NotRunning){helper.kill();helper.waitForFinished(1500);}}
bool Mission::feedFresh()const{
 if(!m_live||m_paused||frame.contains("error"))return false;
 auto generated=QDateTime::fromString(frame["generated"].toString(),Qt::ISODateWithMs);
 if(!generated.isValid())generated=QDateTime::fromString(frame["generated"].toString(),Qt::ISODate);
 qint64 age=generated.msecsTo(QDateTime::currentDateTimeUtc());return generated.isValid()&&age>=0&&age<=15000;
}
QString Mission::feedStatus()const{
 if(m_paused)return "PAUSED · current satellite markers withheld";
 if(frame.isEmpty())return "Waiting for first live calculation · markers withheld";
 if(frame.contains("error"))return frame["error"].toString();
 if(!feedFresh())return "Live calculation missing, stale or future-dated · markers withheld";
 int usable=frame["satellites"].toObject()["objects"].toArray().size();
 return QString("LIVE LOCAL DATA · %1 current stations · visibility uncertain").arg(usable);
}
QJsonObject Mission::liveStation(int i)const{
 if(!feedFresh())return {};
 for(auto v:frame["satellites"].toObject()["objects"].toArray()){auto r=v.toObject();if(r["id"].toInt()==(i?48274:25544)){
 auto epoch=QDateTime::fromString(r["epoch"].toString(),Qt::ISODate);qint64 age=epoch.msecsTo(QDateTime::currentDateTimeUtc());
 if(epoch.isValid()&&age>=-21600000LL&&age<=172800000LL)return r;
 }}return {};
}
void Mission::applyFrame(QJsonObject data)
{
    const double longitude = data["observer"].toObject()["lon"].toDouble(std::numeric_limits<double>::quiet_NaN());
    if (std::isfinite(longitude) && longitude >= -180 && longitude <= 180)
        m_centreLongitude = longitude;
    frame = data;
    m_live = true;
    emit changed();
    update();
}
void Mission::startLive(QString runtime,QString bridge,QString state){
 m_live=true;runtimePath=runtime;bridgePath=bridge;statePath=state;
 timeout.setSingleShot(true);timeout.setInterval(12000);
 connect(&timeout,&QTimer::timeout,this,[this]{helper.kill();applyFrame(QJsonObject{{"error","Local calculation timed out; markers withheld"}});});
 connect(&helper,&QProcess::readyReadStandardOutput,this,[this]{pending+=helper.readAllStandardOutput();if(pending.size()>2097152){helper.kill();pending.clear();applyFrame(QJsonObject{{"error","Local response too large; markers withheld"}});}});
 connect(&helper,qOverload<int,QProcess::ExitStatus>(&QProcess::finished),this,[this](int code,QProcess::ExitStatus status){timeout.stop();pending+=helper.readAllStandardOutput();auto doc=QJsonDocument::fromJson(pending);pending.clear();if(code==0&&status==QProcess::NormalExit&&doc.isObject()&&doc.object()["mode"]=="live")applyFrame(doc.object());else applyFrame(QJsonObject{{"error","Live calculation unavailable. Check the observing location, terrain and cached data in OMANOVA."}});});
 connect(&helper,&QProcess::errorOccurred,this,[this](QProcess::ProcessError){timeout.stop();applyFrame(QJsonObject{{"error","Unable to run the installed OMANOVA calculation helper"}});});
 emit changed();update();refresh.setInterval(5000);connect(&refresh,&QTimer::timeout,this,&Mission::poll);refresh.start();poll();
}
void Mission::poll(){
 if(m_paused||!isVisible()||(window()&&(window()->visibility()==QWindow::Minimized||window()->visibility()==QWindow::Hidden))||helper.state()!=QProcess::NotRunning)return;
 if(!QFileInfo::exists(runtimePath+"/.venv/bin/python")||!QFileInfo::exists(bridgePath)){applyFrame(QJsonObject{{"error","Installed runtime or read-only bridge is missing"}});return;}
 pending.clear();auto env=QProcessEnvironment::systemEnvironment();env.insert("PYTHONDONTWRITEBYTECODE","1");env.insert("OPENBLAS_NUM_THREADS","1");helper.setProcessEnvironment(env);helper.setWorkingDirectory(QFileInfo(bridgePath).absolutePath());helper.setProgram(runtimePath+"/.venv/bin/python");helper.setArguments({"-B",bridgePath,"--runtime",runtimePath,"--state",statePath});helper.start();timeout.start();
}
QPointF Mission::skyPoint(double az,double el,const QRectF&r)const{double a=qDegreesToRadians(az),radius=r.width()*.5*(90-el)/90.;return r.center()+QPointF(-sin(a)*radius,-cos(a)*radius);}
double Mission::viewLongitude()const{return std::remainder(m_centreLongitude + m_elapsed*.5,360.);}
QPointF Mission::globePoint(double lon,double lat,const QPointF&center,double r,double scale,double*front)const{
 double a=qDegreesToRadians(lon-viewLongitude()),b=qDegreesToRadians(lat),tilt=qDegreesToRadians(20.);
 double x=cos(b)*sin(a),y=sin(b)*cos(tilt)-cos(b)*cos(a)*sin(tilt),z=sin(b)*sin(tilt)+cos(b)*cos(a)*cos(tilt);
 if(front){*front=z;}
 return center+QPointF(x*r*scale,-y*r*scale);
}
void Mission::drawLiveSky(QPainter*p,QRectF area){
 double r=qMax(25.,qMin(area.width()*.5-38,area.height()*.5-38));QRectF disc(area.center()-QPointF(r,r),QSizeF(r*2,r*2));
 p->setBrush(QColor("#07182a"));p->setPen(QPen(QColor("#426f83"),1));p->drawEllipse(disc);
 for(int i=1;i<=4;i++){p->setBrush(Qt::NoBrush);p->setPen(QPen(QColor("#245066"),.7));p->drawEllipse(disc.center(),r*i/4.,r*i/4.);}
 for(int a=0;a<360;a+=5){double rad=qDegreesToRadians(double(a));QPointF d(sin(rad),-cos(rad));p->setPen(QPen(QColor("#4c8496"),.8));p->drawLine(disc.center()+d*(r+2),disc.center()+d*(r+(a%30?6:12)));}
 label(p,disc.center()+QPointF(-6,-r-20),"N",17);label(p,disc.center()+QPointF(-6,r+29),"S",17);label(p,disc.center()+QPointF(-r-29,6),"E",17);label(p,disc.center()+QPointF(r+18,6),"W",17);
 if(!feedFresh()){label(p,disc.center()+QPointF(-60,0),m_paused?"PAUSED":"SKY UNAVAILABLE",12,muted);return;}
 auto chart=frame["chart"].toObject();QMap<int,QPointF> points;
 for(auto v:chart["stars"].toArray()){auto s=v.toObject();QPointF pt=skyPoint(s["az"].toDouble(),s["el"].toDouble(),disc);points.insert(s["id"].toInt(),pt);}
 p->setPen(QPen(QColor(95,169,197,100),.8));for(auto v:chart["lines"].toArray()){auto line=v.toObject();int a=line["a"].toInt(),b=line["b"].toInt();if(points.contains(a)&&points.contains(b))p->drawLine(points[a],points[b]);}
 for(auto v:chart["stars"].toArray()){auto s=v.toObject();double sz=qBound(.5,2.0-s["mag"].toDouble()*.30,2.1);p->setBrush(s["clear"].toBool()?QColor("#d4e9fa"):QColor("#42596c"));p->setPen(Qt::NoPen);p->drawEllipse(points[s["id"].toInt()],sz,sz);}
 auto h=chart["horizon"].toArray();if(h.size()==360){QPainterPath mask;for(int a=0;a<360;a++){auto pt=skyPoint(a,h[a].toDouble(),disc);if(!a)mask.moveTo(pt);else mask.lineTo(pt);}mask.closeSubpath();p->setBrush(Qt::NoBrush);p->setPen(QPen(QColor(245,185,100,120),1,Qt::DotLine));p->drawPath(mask);}
 QVector<QRectF> occupied;
 for(auto v:chart["objects"].toArray()){
  auto o=v.toObject();QPointF pt=skyPoint(o["az"].toDouble(),o["el"].toDouble(),disc);p->setBrush(amber);p->setPen(Qt::NoPen);p->drawEllipse(pt,3,3);
  QFont font("DejaVu Sans");font.setPixelSize(12);double width=QFontMetricsF(font).horizontalAdvance(o["name"].toString())+6;
  QPointF text(qBound(area.left()+8,pt.x()+8,area.right()-width-8),pt.y()-8);QRectF box;
  for(int attempt=0;attempt<10;attempt++){box=QRectF(text+QPointF(-2,-13),QSizeF(width,17));bool overlap=false;for(auto used:occupied)if(used.intersects(box)){overlap=true;break;}if(!overlap)break;text.ry()+=18;}
  occupied<<box;
  if(QLineF(pt,text).length()>20){p->setPen(QPen(QColor(240,181,102,100),.7));p->drawLine(pt,text+QPointF(-2,-4));}
  label(p,text,o["name"].toString(),12,amber);
 }
 int above=0;
 for(int i=0;i<2;i++){auto s=liveStation(i);if(s.isEmpty()||s["el"].toDouble()<0)continue;above++;QColor c=i==m_selection?cyan:amber;
 if(m_trails){QPainterPath path;bool begun=false;for(auto v:s["path"].toArray()){auto pt=v.toObject();QPointF q=skyPoint(pt["az"].toDouble(),pt["el"].toDouble(),disc);if(!begun){path.moveTo(q);begun=true;}else path.lineTo(q);}p->setBrush(Qt::NoBrush);p->setPen(QPen(c,1.2,Qt::DashLine));p->drawPath(path);}
 QPointF pt=skyPoint(s["az"].toDouble(),s["el"].toDouble(),disc);hits[i]=pt;diamond(p,pt,c,i==m_selection);label(p,QPointF(qMin(pt.x()+12,area.right()-100),pt.y()-10),name(i),13,c);
 }
 if(!above)label(p,QPointF(area.left()+16,area.bottom()-5),chart["sunAltitude"].toDouble()>0?"Daylight · no station above your horizon":"No current station above your horizon",11,muted);
}
void Mission::drawLiveEarth(QPainter*p,QRectF area){
 double r=qMin(area.width(),area.height())*.445;QPointF center=area.center();QRectF disc(center-QPointF(r,r),QSizeF(r*2,r*2));
 QRadialGradient halo(center,r*1.12);halo.setColorAt(.86,Qt::transparent);halo.setColorAt(.90,QColor(48,162,248,90));halo.setColorAt(1,Qt::transparent);p->setPen(Qt::NoPen);p->setBrush(halo);p->drawEllipse(center,r*1.12,r*1.12);
 bakeGlobe();
 p->drawImage(disc,globe);
 if(!feedFresh())return;
 auto observer=frame["observer"].toObject();double z;QPointF home=globePoint(observer["lon"].toDouble(),observer["lat"].toDouble(),center,r,1,&z);
 if(z>=0){p->setBrush(white);p->setPen(Qt::NoPen);p->drawEllipse(home,3,3);if(area.width()>480)label(p,home+QPointF(6,15),"YOUR LOCATION",10,muted);}
 for(int i=0;i<2;i++){auto s=liveStation(i);if(s.isEmpty())continue;QColor c=i==m_selection?cyan:amber;
 if(m_trails){QPainterPath path;bool begun=false;for(auto v:s["groundTrack"].toArray()){auto a=v.toArray();QPointF pt=globePoint(a[0].toDouble(),a[1].toDouble(),center,r,1.004,&z);if(z<0){begun=false;continue;}if(!begun){path.moveTo(pt);begun=true;}else path.lineTo(pt);}p->setBrush(Qt::NoBrush);p->setPen(QPen(QColor(c.red(),c.green(),c.blue(),170),1.2,Qt::DashLine));p->drawPath(path);}
 double scale=1+s["altitudeKm"].toDouble()/6378.137;QPointF pt=globePoint(s["lon"].toDouble(),s["lat"].toDouble(),center,r,scale,&z);
 if(z<0){continue;}
 hits[2+i]=pt;diamond(p,pt,c,i==m_selection);if(area.width()>480||i==m_selection)label(p,QPointF(qMin(pt.x()+12,area.right()-95),pt.y()-14),name(i),13,c);
 }
 auto selected=liveStation(m_selection);if(!selected.isEmpty()){globePoint(selected["lon"].toDouble(),selected["lat"].toDouble(),center,r,1,&z);if(z<0)label(p,QPointF(area.left()+16,area.top()+20),name(m_selection)+" · far side of Earth",11,muted);}
 if(area.width()>480)label(p,QPointF(area.left()+16,area.bottom()-5),"Historical Earth imagery · decorative light / rotation",10,muted);
}
