#pragma once
#include <QQuickPaintedItem>
#include <QTimer>
#include <QElapsedTimer>
#include <QImage>
class Mission : public QQuickPaintedItem {
 Q_OBJECT
 Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY changed)
 Q_PROPERTY(bool reduced READ reduced WRITE setReduced NOTIFY changed)
 Q_PROPERTY(bool trails READ trails WRITE setTrails NOTIFY changed)
 Q_PROPERTY(int selection READ selection WRITE setSelection NOTIFY changed)
 Q_PROPERTY(int view READ view WRITE setView NOTIFY changed)
 Q_PROPERTY(double elapsed READ elapsed NOTIFY changed)
 Q_PROPERTY(QString detail READ detail NOTIFY changed)
public:
 Mission(QQuickItem *parent=nullptr);
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
 QTimer timer;QElapsedTimer clock;QImage texture,globe;QVector<QPointF> stars;QVector<double> sizes;
 QRectF skyRect,earthRect;QVector<QPointF> hits;
 QPointF satellite(int,double,const QRectF&)const;
 void drawSky(QPainter*,QRectF);void drawEarth(QPainter*,QRectF);void bakeGlobe();
};
