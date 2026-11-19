#pragma once

#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

#include <QObject>
#include <QSystemTrayIcon>
#include <QAction>
#include <QMenu>
#include <QIcon>
#include <QPixmap>
#include <QPainter>

namespace Zalos::Core::Platform {

class SystemTrayController : public QObject {
    Q_OBJECT

public:
    static inline SystemTrayController* s_instance = nullptr;
    explicit SystemTrayController(QObject* parent = nullptr);
    ~SystemTrayController() override;

    void setUnreadCount(int count, bool hasMentions = false);
    void setHasMentions(bool hasMentions);
    void setAntiPeeking(bool on);
    void setLanguage(const QString& lang);
    void setWindowVisible(bool visible);
    void setCallState(const QString& phase, const QString& peerName, bool isVideo,
                      bool muted, bool speakerOff, bool cameraOn, bool screenShareOn);
    QString callPhase() const { return m_callPhase; }
    QString toolTip() const;
    bool isVisible() const;

    QAction* callStatusAction() const { return m_callStatusAction; }
    QAction* callAcceptAction() const { return m_callAcceptAction; }
    QAction* callAcceptNoCamAction() const { return m_callAcceptNoCamAction; }
    QAction* callRejectAction() const { return m_callRejectAction; }
    QAction* callMuteAction() const { return m_callMuteAction; }
    QAction* callSpeakerAction() const { return m_callSpeakerAction; }
    QAction* callCameraAction() const { return m_callCameraAction; }
    QAction* callScreenShareAction() const { return m_callScreenShareAction; }
    QAction* callHangupAction() const { return m_callHangupAction; }

signals:
    void toggleWindowRequested();
    void quitRequested();
    void toggleDarkModeRequested();
    void antiPeekingToggled(bool on);
    void showCallWindowRequested();
    void acceptCallRequested(bool withoutCamera);
    void rejectCallRequested();
    void hangupCallRequested();
    void toggleCallMuteRequested();
    void toggleCallSpeakerRequested();
    void toggleCallCameraRequested();
    void toggleCallScreenShareRequested();

public slots:
    void showMessage(const QString& title, const QString& message);

private slots:
    void onTrayActivated(QSystemTrayIcon::ActivationReason reason);

private:
    void setupMenu();
    QIcon createBadgeIcon(int count, bool hasMentions);
    void refreshIconAndTooltip();
    void retranslate();
    QString L(const QString& vi, const QString& en) const { return m_language == QLatin1String("en") ? en : vi; }

    QSystemTrayIcon* m_trayIcon{nullptr};
    QMenu* m_trayMenu{nullptr};
    int m_unreadCount{0};
    bool m_hasMentions{false};
    bool m_antiPeeking{false};
    QString m_callPhase;
    QString m_callPeerName;
    bool m_callIsVideo{false};
    bool m_callMuted{false};
    bool m_callSpeakerOff{false};
    bool m_callCameraOn{false};
    bool m_callScreenShareOn{false};
    QAction* m_callStatusAction{nullptr};
    QAction* m_callAcceptAction{nullptr};
    QAction* m_callAcceptNoCamAction{nullptr};
    QAction* m_callRejectAction{nullptr};
    QAction* m_callMuteAction{nullptr};
    QAction* m_callSpeakerAction{nullptr};
    QAction* m_callCameraAction{nullptr};
    QAction* m_callScreenShareAction{nullptr};
    QAction* m_callHangupAction{nullptr};
    QAction* m_callSeparator{nullptr};
    QAction* m_antiPeekAction{nullptr};
    QAction* m_openAction{nullptr};
    QAction* m_themeAction{nullptr};
    QAction* m_quitAction{nullptr};
    bool m_windowVisible{true};
    QString m_language{QStringLiteral("vi")};
    QPixmap m_basePixmap;
    int m_lastBadgeCount{-1};
    bool m_lastBadgeMentions{false};
    bool m_lastBadgeAntiPeeking{false};
    QString m_lastBadgeCallPhase;
};

}
