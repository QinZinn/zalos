#include "system_tray.h"

#include <QJSEngine>
#include <QApplication>
#include <QPainter>
#include <QPainterPath>
#include <QFont>
#include <QStyle>
#include <QDBusConnection>
#include <QDBusMessage>

namespace Zalos::Core::Platform {

SystemTrayController::SystemTrayController(QObject* parent)
    : QObject(parent) {
    s_instance = this;
    QObject::connect(this, &QObject::destroyed, [](QObject* gone) {
        if (static_cast<QObject*>(s_instance) == gone) s_instance = nullptr;
    });
    m_trayIcon = new QSystemTrayIcon(this);
    m_trayIcon->setIcon(createBadgeIcon(0, false));
    setupMenu();
    retranslate();

    connect(m_trayIcon, &QSystemTrayIcon::activated, this, &SystemTrayController::onTrayActivated);
    m_trayIcon->show();
}

SystemTrayController::~SystemTrayController() {
    if (m_trayIcon) {
        m_trayIcon->hide();
    }
}

void SystemTrayController::setupMenu() {
    m_trayMenu = new QMenu();

    m_callStatusAction = m_trayMenu->addAction(QString());
    connect(m_callStatusAction, &QAction::triggered, this, &SystemTrayController::showCallWindowRequested);

    m_callAcceptAction = m_trayMenu->addAction(QString());
    connect(m_callAcceptAction, &QAction::triggered, this, [this]() { emit acceptCallRequested(false); });

    m_callAcceptNoCamAction = m_trayMenu->addAction(QString());
    connect(m_callAcceptNoCamAction, &QAction::triggered, this, [this]() { emit acceptCallRequested(true); });

    m_callRejectAction = m_trayMenu->addAction(QString());
    connect(m_callRejectAction, &QAction::triggered, this, &SystemTrayController::rejectCallRequested);

    m_callMuteAction = m_trayMenu->addAction(QString());
    m_callMuteAction->setCheckable(true);
    connect(m_callMuteAction, &QAction::triggered, this, &SystemTrayController::toggleCallMuteRequested);

    m_callSpeakerAction = m_trayMenu->addAction(QString());
    m_callSpeakerAction->setCheckable(true);
    connect(m_callSpeakerAction, &QAction::triggered, this, &SystemTrayController::toggleCallSpeakerRequested);

    m_callCameraAction = m_trayMenu->addAction(QString());
    m_callCameraAction->setCheckable(true);
    connect(m_callCameraAction, &QAction::triggered, this, &SystemTrayController::toggleCallCameraRequested);

    m_callScreenShareAction = m_trayMenu->addAction(QString());
    m_callScreenShareAction->setCheckable(true);
    connect(m_callScreenShareAction, &QAction::triggered, this, &SystemTrayController::toggleCallScreenShareRequested);

    m_callHangupAction = m_trayMenu->addAction(QString());
    connect(m_callHangupAction, &QAction::triggered, this, &SystemTrayController::hangupCallRequested);

    m_callSeparator = m_trayMenu->addSeparator();
    for (QAction* a : {m_callStatusAction, m_callAcceptAction, m_callAcceptNoCamAction, m_callRejectAction,
                       m_callMuteAction, m_callSpeakerAction, m_callCameraAction, m_callScreenShareAction,
                       m_callHangupAction, m_callSeparator}) {
        a->setVisible(false);
    }

    m_openAction = m_trayMenu->addAction(QString());
    connect(m_openAction, &QAction::triggered, this, &SystemTrayController::toggleWindowRequested);

    m_themeAction = m_trayMenu->addAction(QString());
    connect(m_themeAction, &QAction::triggered, this, &SystemTrayController::toggleDarkModeRequested);

    m_antiPeekAction = m_trayMenu->addAction(QString());
    m_antiPeekAction->setCheckable(true);
    connect(m_antiPeekAction, &QAction::triggered, this, &SystemTrayController::antiPeekingToggled);

    m_trayMenu->addSeparator();

    m_quitAction = m_trayMenu->addAction(QString());
    connect(m_quitAction, &QAction::triggered, this, &SystemTrayController::quitRequested);

    m_trayIcon->setContextMenu(m_trayMenu);
}

void SystemTrayController::setLanguage(const QString& lang) {
    const QString next = lang == QLatin1String("en") ? QStringLiteral("en") : QStringLiteral("vi");
    if (m_language == next) return;
    m_language = next;
    retranslate();
}

void SystemTrayController::setCallState(const QString& phase, const QString& peerName, bool isVideo,
                                        bool muted, bool speakerOff, bool cameraOn, bool screenShareOn) {
    const bool active = !phase.isEmpty() && phase != QLatin1String("ended");
    const QString normalizedPhase = active ? phase : QString();
    const QString normalizedPeer = active ? peerName : QString();
    if (m_callPhase == normalizedPhase && m_callPeerName == normalizedPeer
        && m_callIsVideo == isVideo && m_callMuted == muted
        && m_callSpeakerOff == speakerOff && m_callCameraOn == cameraOn
        && m_callScreenShareOn == screenShareOn) {
        return;
    }
    m_callPhase = normalizedPhase;
    m_callPeerName = normalizedPeer;
    m_callIsVideo = active && isVideo;
    m_callMuted = active && muted;
    m_callSpeakerOff = active && speakerOff;
    m_callCameraOn = active && cameraOn;
    m_callScreenShareOn = active && screenShareOn;
    retranslate();
}

void SystemTrayController::retranslate() {
    const bool active = !m_callPhase.isEmpty() && m_callPhase != QLatin1String("ended");
    const bool incoming = m_callPhase == QLatin1String("incoming");
    const bool inCall = active && !incoming;
    const QString peer = m_callPeerName.isEmpty() ? QStringLiteral("Zalo") : m_callPeerName;
    if (m_callStatusAction) {
        m_callStatusAction->setVisible(active);
        m_callStatusAction->setText(
            incoming ? L(QStringLiteral("Cuộc gọi đến: %1 (Mở cửa sổ)"), QStringLiteral("Incoming call: %1 (Open window)")).arg(peer)
                     : L(QStringLiteral("Đang gọi: %1 (Mở cửa sổ)"), QStringLiteral("In call: %1 (Open window)")).arg(peer));
    }
    if (m_callAcceptAction) {
        m_callAcceptAction->setVisible(incoming);
        m_callAcceptAction->setText(m_callIsVideo ? L(QStringLiteral("Trả lời bằng video"), QStringLiteral("Answer with video"))
                                                  : L(QStringLiteral("Trả lời cuộc gọi"), QStringLiteral("Answer call")));
    }
    if (m_callAcceptNoCamAction) {
        m_callAcceptNoCamAction->setVisible(incoming && m_callIsVideo);
        m_callAcceptNoCamAction->setText(L(QStringLiteral("Trả lời không mở camera"), QStringLiteral("Answer without camera")));
    }
    if (m_callRejectAction) {
        m_callRejectAction->setVisible(incoming);
        m_callRejectAction->setText(L(QStringLiteral("Từ chối cuộc gọi"), QStringLiteral("Decline call")));
    }
    if (m_callMuteAction) {
        m_callMuteAction->setVisible(inCall);
        m_callMuteAction->setChecked(m_callMuted);
        m_callMuteAction->setText(L(QStringLiteral("Tắt micro"), QStringLiteral("Mute microphone")));
    }
    if (m_callSpeakerAction) {
        m_callSpeakerAction->setVisible(inCall);
        m_callSpeakerAction->setChecked(m_callSpeakerOff);
        m_callSpeakerAction->setText(L(QStringLiteral("Tắt loa"), QStringLiteral("Mute speaker")));
    }
    if (m_callCameraAction) {
        m_callCameraAction->setVisible(inCall && m_callIsVideo);
        m_callCameraAction->setChecked(m_callCameraOn);
        m_callCameraAction->setText(L(QStringLiteral("Bật camera"), QStringLiteral("Camera on")));
    }
    if (m_callScreenShareAction) {
        m_callScreenShareAction->setVisible(m_callPhase == QLatin1String("connected"));
        m_callScreenShareAction->setChecked(m_callScreenShareOn);
        m_callScreenShareAction->setText(L(QStringLiteral("Chia sẻ màn hình"), QStringLiteral("Share screen")));
    }
    if (m_callHangupAction) {
        m_callHangupAction->setVisible(inCall);
        m_callHangupAction->setText(L(QStringLiteral("Kết thúc cuộc gọi"), QStringLiteral("End call")));
    }
    if (m_callSeparator) m_callSeparator->setVisible(active);

    if (m_openAction) m_openAction->setText(L(QStringLiteral("Mở Zalos"), QStringLiteral("Open Zalos")));
    if (m_themeAction) m_themeAction->setText(L(QStringLiteral("Chuyển chế độ Sáng / Tối"), QStringLiteral("Toggle light / dark mode")));
    if (m_antiPeekAction) m_antiPeekAction->setText(L(QStringLiteral("Chống nhìn lén"), QStringLiteral("Anti-peeking")));
    if (m_quitAction) m_quitAction->setText(L(QStringLiteral("Thoát hoàn toàn"), QStringLiteral("Quit")));
    refreshIconAndTooltip();
}

void SystemTrayController::setWindowVisible(bool visible) {
    if (m_openAction) {
        m_openAction->setText(visible ? L(QStringLiteral("Ẩn Zalos"), QStringLiteral("Hide Zalos"))
                                      : L(QStringLiteral("Mở Zalos"), QStringLiteral("Open Zalos")));
    }
}

void SystemTrayController::setUnreadCount(int count, bool hasMentions) {
    if (m_unreadCount == count && m_hasMentions == hasMentions) return;
    m_unreadCount = count;
    m_hasMentions = hasMentions;
    refreshIconAndTooltip();

    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.isConnected()) {
        QDBusMessage signal = QDBusMessage::createSignal(
            QStringLiteral("/com/canonical/unity/launcherentry/zalos"),
            QStringLiteral("com.canonical.Unity.LauncherEntry"),
            QStringLiteral("Update"));
        QVariantMap properties;
        properties.insert(QStringLiteral("count"), qint64(m_unreadCount));
        properties.insert(QStringLiteral("count-visible"), m_unreadCount > 0);
        properties.insert(QStringLiteral("urgent"), m_hasMentions);
        signal << QStringLiteral("application://zalos.desktop") << properties;
        bus.send(signal);
    }
}

void SystemTrayController::setHasMentions(bool hasMentions) {
    if (m_hasMentions == hasMentions) return;
    m_hasMentions = hasMentions;
    refreshIconAndTooltip();
}

void SystemTrayController::setAntiPeeking(bool on) {
    if (m_antiPeekAction) m_antiPeekAction->setChecked(on);
    if (m_antiPeeking == on) return;
    m_antiPeeking = on;
    refreshIconAndTooltip();
}

void SystemTrayController::refreshIconAndTooltip() {
    m_trayIcon->setIcon(createBadgeIcon(m_unreadCount, m_hasMentions));
    QString tip;
    if (!m_callPhase.isEmpty() && m_callPhase != QLatin1String("ended")) {
        const QString peer = m_callPeerName.isEmpty() ? QStringLiteral("Zalo") : m_callPeerName;
        if (m_callPhase == QLatin1String("incoming")) {
            tip += L(QStringLiteral("Cuộc gọi đến: %1\n"), QStringLiteral("Incoming call: %1\n")).arg(peer);
        } else if (m_callPhase == QLatin1String("connected")) {
            tip += L(QStringLiteral("Đang trong cuộc gọi: %1%2\n"), QStringLiteral("In call: %1%2\n"))
                       .arg(peer, m_callMuted ? L(QStringLiteral(" (Đã tắt micro)"), QStringLiteral(" (Muted)")) : QString());
        } else {
            tip += L(QStringLiteral("Đang gọi: %1\n"), QStringLiteral("Calling: %1\n")).arg(peer);
        }
    }
    tip += m_unreadCount > 0
        ? L(QStringLiteral("Zalos - Có %1 tin nhắn chưa đọc"), QStringLiteral("Zalos - %1 unread messages")).arg(m_unreadCount)
        : L(QStringLiteral("Zalos - Ứng dụng chat bảo mật cho Linux"), QStringLiteral("Zalos - private chat for Linux"));
    if (m_hasMentions) tip += L(QStringLiteral("\nCó tin nhắn nhắc tên bạn (@)"), QStringLiteral("\nYou were mentioned (@)"));
    if (m_antiPeeking) tip += L(QStringLiteral("\nĐang bật chống nhìn lén"), QStringLiteral("\nAnti-peeking is on"));
    m_trayIcon->setToolTip(tip);
}

QString SystemTrayController::toolTip() const {
    return m_trayIcon ? m_trayIcon->toolTip() : QString();
}

bool SystemTrayController::isVisible() const {
    return m_trayIcon && m_trayIcon->isVisible();
}

void SystemTrayController::showMessage(const QString& title, const QString& message) {
    if (m_trayIcon) {
        m_trayIcon->showMessage(title, message, QSystemTrayIcon::Information, 3000);
    }
}

void SystemTrayController::onTrayActivated(QSystemTrayIcon::ActivationReason reason) {
    if (reason == QSystemTrayIcon::Trigger || reason == QSystemTrayIcon::DoubleClick) {
        emit toggleWindowRequested();
    }
}

QIcon SystemTrayController::createBadgeIcon(int count, bool hasMentions) {
    QIcon baseIcon(":/Zalos/assets/icons/zalos.svg");
    QPixmap pixmap = baseIcon.pixmap(64, 64);
    if (pixmap.isNull()) {
        pixmap = QPixmap(64, 64);
        pixmap.fill(Qt::transparent);
        QPainter p(&pixmap);
        p.setRenderHint(QPainter::Antialiasing);
        p.setBrush(QColor("#0068FF"));
        p.setPen(Qt::NoPen);
        p.drawEllipse(4, 4, 56, 56);
        p.setPen(Qt::white);
        QFont f = p.font();
        f.setPixelSize(34);
        f.setBold(true);
        p.setFont(f);
        p.drawText(QRect(4, 4, 56, 56), Qt::AlignCenter, "Z");
    }

    QPainter painter(&pixmap);
    painter.setRenderHint(QPainter::Antialiasing);

    if (count > 0) {
        const QString badgeText = (count > 99) ? QStringLiteral("99+") : QString::number(count);

        const int fontSize = (badgeText.length() >= 3) ? 22 : (badgeText.length() == 2 ? 26 : 28);
        QFont badgeFont = painter.font();
        badgeFont.setPixelSize(fontSize);
        badgeFont.setBold(true);
        badgeFont.setStyleStrategy(QFont::PreferAntialias);
        painter.setFont(badgeFont);

        QFontMetrics fm(badgeFont);
        const int textWidth = fm.horizontalAdvance(badgeText);
        const int badgeHeight = 40;
        const int badgeWidth = qMin(62, qMax(badgeHeight, textWidth + 16));

        const int badgeRight = 64;
        const int badgeBottom = 64;
        const int badgeX = qMax(2, badgeRight - badgeWidth);
        const int badgeY = badgeBottom - badgeHeight;
        const QRectF badgeRect(badgeX, badgeY, badgeWidth, badgeHeight);

        const QColor badgeColor = hasMentions ? QColor("#DC2626") : QColor("#EF4444");

        painter.setBrush(badgeColor);
        painter.setPen(QPen(QColor(15, 23, 42, 230), 2.0));
        painter.drawRoundedRect(badgeRect, badgeHeight / 2.0, badgeHeight / 2.0);

        painter.setPen(Qt::white);
        painter.drawText(badgeRect, Qt::AlignCenter, badgeText);
    }

    if (m_antiPeeking) {
        painter.setBrush(QColor("#081B3A"));
        painter.setPen(QPen(Qt::white, 2));
        painter.drawEllipse(2, 36, 26, 26);
        painter.setPen(QPen(Qt::white, 2.2));
        painter.setBrush(Qt::NoBrush);
        painter.drawEllipse(QRectF(8, 44.5, 14, 9));
        painter.drawEllipse(QRectF(13, 47, 4, 4));
        painter.drawLine(QPointF(7, 56), QPointF(23, 42));
    }

    if (!m_callPhase.isEmpty() && m_callPhase != QLatin1String("ended")) {
        const QColor callColor = m_callPhase == QLatin1String("connected") ? QColor("#22C55E") : QColor("#F59E0B");
        painter.setBrush(callColor);
        painter.setPen(QPen(QColor(15, 23, 42, 230), 2.0));
        painter.drawEllipse(QRectF(36, 2, 26, 26));
        QPainterPath handset;
        handset.moveTo(43.5, 11.5);
        handset.quadTo(44.5, 17.5, 51.5, 19.5);
        handset.lineTo(54.0, 17.2);
        handset.lineTo(51.8, 15.6);
        handset.lineTo(50.2, 16.8);
        handset.quadTo(47.2, 15.5, 45.8, 12.6);
        handset.lineTo(47.0, 11.0);
        handset.lineTo(45.4, 9.0);
        handset.closeSubpath();
        painter.setBrush(Qt::white);
        painter.setPen(QPen(Qt::white, 1.4, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        painter.drawPath(handset);
    }

    return QIcon(pixmap);
}

}
