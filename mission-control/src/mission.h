#pragma once
#include <QQuickPaintedItem>
#include <QTimer>
#include <QElapsedTimer>
#include <QImage>
#include <QProcess>
#include <QJsonObject>
#include <QVariantMap>
#include <QDateTime>
class Mission : public QQuickPaintedItem {
 Q_OBJECT
 Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY changed)
 Q_PROPERTY(bool reduced READ reduced WRITE setReduced NOTIFY changed)
 Q_PROPERTY(bool trails READ trails WRITE setTrails NOTIFY changed)
 Q_PROPERTY(int selection READ selection WRITE setSelection NOTIFY changed)
 Q_PROPERTY(int view READ view WRITE setView NOTIFY changed)
 Q_PROPERTY(double elapsed READ elapsed NOTIFY changed)
 Q_PROPERTY(QString detail READ detail NOTIFY changed)
 Q_PROPERTY(bool live READ live NOTIFY changed)
 Q_PROPERTY(bool feedFresh READ feedFresh NOTIFY changed)
 Q_PROPERTY(QString feedStatus READ feedStatus NOTIFY changed)
 Q_PROPERTY(QVariantMap liveData READ liveData NOTIFY changed)
public:
 Mission(QQuickItem *parent=nullptr);
 ~Mission() override;
 bool live()const{return m_live;}
 bool feedFresh()const;
 QString feedStatus()const;
 QVariantMap liveData()const{return frame.toVariantMap();}
 void startLive(QString runtime,QString bridge,QString state);
 void applyFrame(QJsonObject data);
 bool paused()const{return m_paused;} bool reduced()const{return m_reduced;} bool trails()const{return m_trails;}
 int selection()const{return m_selection;} int view()const{return m_view;} double elapsed()const{return m_elapsed;}
 void setPaused(bool);void setReduced(bool);void setTrails(bool);void setSelection(int);void setView(int);
 QString detail()const;
 void paint(QPainter*)override;
 Q_INVOKABLE void reset();
signals:void changed();
protected:void mousePressEvent(QMouseEvent*)override;
private:
 bool m_paused=false,m_reduced=false,m_trails=true;int m_selection=0,m_view=0;double m_elapsed=0,m_textureTime=-100;
 bool m_live=false;QJsonObject frame;QProcess helper;QTimer refresh,timeout;QByteArray pending;QString runtimePath,bridgePath,statePath;
 void poll();
 QJsonObject liveStation(int i)const;
 QPointF skyPoint(double az,double el,const QRectF&r)const;
 QPointF globePoint(double lon,double lat,const QPointF&center,double r,double scale,double *front=nullptr)const;
 double viewLongitude()const;
 void drawLiveSky(QPainter*,QRectF);void drawLiveEarth(QPainter*,QRectF);
 QTimer timer;QElapsedTimer clock;QImage texture,globe;QVector<QPointF> stars;QVector<double> sizes;
 QRectF skyRect,earthRect;QVector<QPointF> hits;
 QPointF satellite(int,double,const QRectF&)const;
 void drawSky(QPainter*,QRectF);void drawEarth(QPainter*,QRectF);void bakeGlobe();
};
