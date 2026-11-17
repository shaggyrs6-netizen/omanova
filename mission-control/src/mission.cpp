#include "mission.h"
#include <QPainter>
#include <QPainterPath>
#include <QRandomGenerator>
#include <QMouseEvent>
#include <QQuickWindow>
#include <QtMath>
#include <algorithm>
static const QColor cyan("#5de7ef"),white("#edf5fa"),muted("#90aabd"),amber("#f9bb64");
static QString name(int i){return i==0?"ISS":"TIANGONG";}
static void label(QPainter*p,QPointF pos,QString text,int size,QColor color=white){QFont f("DejaVu Sans");f.setPixelSize(size);p->setFont(f);p->setPen(color);p->drawText(pos,text);}
static void diamond(QPainter*p,QPointF pos,QColor color,bool selected){
 if(selected){QRadialGradient glow(pos,22);glow.setColorAt(0,QColor(75,230,245,100));glow.setColorAt(1,Qt::transparent);p->setBrush(glow);p->setPen(Qt::NoPen);p->drawEllipse(pos,22,22);}
 QPolygonF poly;poly<<pos+QPointF(0,-6)<<pos+QPointF(6,0)<<pos+QPointF(0,6)<<pos+QPointF(-6,0);p->setPen(QPen(color,1.5));p->setBrush(selected?color:QColor("#081726"));p->drawPolygon(poly);
}
Mission::Mission(QQuickItem*p):QQuickPaintedItem(p){
 setAntialiasing(true);setAcceptedMouseButtons(Qt::LeftButton);texture.load(":/assets/earth.jpg");
 QRandomGenerator rng(4261);for(int i=0;i<650;i++){stars<<QPointF(rng.generateDouble(),rng.generateDouble());sizes<<(.4+rng.generateDouble()*1.25);}
 connect(this,&QQuickItem::windowChanged,this,[this](QQuickWindow*w){if(!w)return;connect(w,&QWindow::visibilityChanged,this,[this](QWindow::Visibility v){if(v==QWindow::Minimized||v==QWindow::Hidden)timer.stop();else if(!m_paused){clock.restart();timer.start();}});});
 clock.start();timer.setInterval(50);connect(&timer,&QTimer::timeout,this,[this]{double dt=qMin(clock.restart()/1000.,.15);if(!m_paused&&isVisible()){m_elapsed+=dt*(m_reduced?.12:1.0);emit changed();update();}});timer.start();
}
void Mission::setPaused(bool v){if(v==m_paused)return;m_paused=v;clock.restart();if(v)timer.stop();else timer.start();emit changed();update();}
void Mission::setReduced(bool v){m_reduced=v;timer.setInterval(v?150:50);emit changed();update();}
void Mission::setTrails(bool v){m_trails=v;emit changed();update();}
void Mission::setSelection(int v){if(v<0||v>1)return;m_selection=v;emit changed();update();}
void Mission::setView(int v){if(v<0||v>2)return;m_view=v;emit changed();update();}
void Mission::reset(){m_elapsed=0;m_textureTime=-100;emit changed();update();}
QString Mission::detail()const{return name(m_selection)+"  /  "+QString::number(238+int(m_elapsed*.7+m_selection*104)%100)+"° bearing  /  "+QString::number(32+int(m_elapsed*.4+m_selection*13)%27)+"° up  /  SAMPLE";}
QPointF Mission::satellite(int i,double t,const QRectF&r)const{
 double a=t*.027+i*2.3-1.7;double radius=r.width()*.5;return r.center()+QPointF(sin(a)*radius*.79,-cos(a*.77)*radius*.58);
}
void Mission::drawSky(QPainter*p,QRectF area){
 const double r=qMax(25.,qMin(area.width()*.5-44,area.height()*.5-44));QRectF disc(area.center().x()-r,area.center().y()-r,2*r,2*r);skyRect=disc;
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
void Mission::bakeGlobe(){
 const int n=600;globe=QImage(n,n,QImage::Format_ARGB32_Premultiplied);globe.fill(Qt::transparent);
 double lon0=qDegreesToRadians(-76.+m_elapsed*.5),lat0=qDegreesToRadians(20.);double sl=sin(lat0),cl=cos(lat0);
 if(texture.isNull())return;
 for(int y=0;y<n;y++){auto line=reinterpret_cast<QRgb*>(globe.scanLine(y));double yy=-(y-(n-1)*.5)/(n*.5-1);
 for(int x=0;x<n;x++){double xx=(x-(n-1)*.5)/(n*.5-1),q=xx*xx+yy*yy;if(q>=1)continue;double z=sqrt(1-q);double lat=asin(yy*cl+z*sl),lon=lon0+atan2(xx,z*cl-yy*sl);
 int tx=int((lon/(2*M_PI)+.5)*texture.width())%texture.width();if(tx<0)tx+=texture.width();int ty=qBound(0,int((.5-lat/M_PI)*texture.height()),texture.height()-1);
 QColor c=texture.pixelColor(tx,ty);double light=qBound(.11,(-xx*.65+yy*.25+z*.60)*1.2,1.05);double rim=pow(1-z,4);
 line[x]=qRgba(qBound(0,int(c.red()*light+rim*9),255),qBound(0,int(c.green()*light+rim*50),255),qBound(0,int(c.blue()*light+rim*80),255),255);
 }}m_textureTime=m_elapsed;
}
void Mission::drawEarth(QPainter*p,QRectF area){
 double r=qMin(area.width(),area.height())*.43;QPointF center=area.center();earthRect=QRectF(center-QPointF(r,r),QSizeF(r*2,r*2));
 QRadialGradient halo(center,r*1.12);halo.setColorAt(0,QColor(20,80,165,0));halo.setColorAt(.86,QColor(25,90,180,0));halo.setColorAt(.90,QColor(48,162,248,95));halo.setColorAt(1,Qt::transparent);p->setPen(Qt::NoPen);p->setBrush(halo);p->drawEllipse(center,r*1.12,r*1.12);
 // Keep the animated texture at five frames per second; markers use 20 fps.
 if(globe.isNull()||fabs(m_elapsed-m_textureTime)>.2){bakeGlobe();}
 p->drawImage(earthRect,globe);
 p->setBrush(Qt::NoBrush);p->setPen(QPen(QColor(91,191,247,145),1.3));p->drawEllipse(earthRect);
 for(int i=1;i>=0;i--){QColor c=i==m_selection?cyan:amber;double phase=m_elapsed*.035+i*2.4;auto point=[&](double a){return center+QPointF(sin(a)*r*1.12,cos(a)*r*.33+sin(a)*r*.38*(i?-.6:1));};
 if(m_trails){for(int k=0;k<180;k++){double a=k*2*M_PI/180,b=(k+1)*2*M_PI/180;p->setPen(QPen(QColor(c.red(),c.green(),c.blue(),cos(a)>0?175:45),1.15,cos(a)>0?Qt::SolidLine:Qt::DashLine));p->drawLine(point(a),point(b));}}
 QPointF pt=point(phase);hits[2+i]=pt;diamond(p,pt,c,i==m_selection);label(p,pt+QPointF(13,-12),name(i),13,c);
 }
}
void Mission::paint(QPainter*p){p->setRenderHint(QPainter::Antialiasing);hits.resize(4);
 QLinearGradient bg(0,0,width(),height());bg.setColorAt(0,QColor("#040d1c"));bg.setColorAt(.5,QColor("#061729"));bg.setColorAt(1,QColor("#020812"));p->fillRect(boundingRect(),bg);
 for(int i=0;i<stars.size();i++){p->setPen(QColor(137,188,216,i%5==0?115:45));p->drawPoint(QPointF(stars[i].x()*width(),stars[i].y()*height()));}
 bool both=m_view==0;QRectF left=both?QRectF(0,0,width()*.5,height()):boundingRect(),right=both?QRectF(width()*.5,0,width()*.5,height()):boundingRect();
 if(m_view!=2){drawSky(p,left);}
 if(m_view!=1){drawEarth(p,right);}
 if(both){p->setPen(QPen(QColor("#1d5264"),1));p->drawLine(QPointF(width()*.5,40),QPointF(width()*.5,height()-30));}
}
void Mission::mousePressEvent(QMouseEvent*e){for(int i=0;i<hits.size();i++){if((i<2&&m_view==2)||(i>=2&&m_view==1))continue;if(QLineF(e->position(),hits[i]).length()<30){setSelection(i%2);e->accept();return;}}e->ignore();}
