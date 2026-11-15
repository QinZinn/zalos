#include "camera_sender.h"
#include "core/media/media_utils.h"

#include <QCamera>
#include <QCameraDevice>
#include <QCameraFormat>
#include <QMediaCaptureSession>
#include <QMediaDevices>
#include <QMutexLocker>
#include <QThread>
#include <QVideoFrame>
#include <QVideoFrameFormat>
#include <QVideoSink>

#include <cstdlib>
#include <limits>

namespace Zalos::Core::Call {

CameraSender::CameraSender(QObject* parent) : QObject(parent) {
    m_clock.start();
}

CameraSender::~CameraSender() {
    stop();
}

bool CameraSender::cameraAvailable() {
    const auto inputs = QMediaDevices::videoInputs();
    for (const auto& dev : inputs) {
        if (!Media::MediaUtils::isIrCamera(dev.description())) return true;
    }
    return false;
}

bool CameraSender::encoderAvailable() {
    return OpenH264::instance().available();
}

bool CameraSender::start(QString* error) {
    if (m_camera) return true;
    if (!encoderAvailable()) {
        if (error) *error = QStringLiteral("no_encoder");
        return false;
    }
    QCameraDevice device;
    const auto inputs = QMediaDevices::videoInputs();
    for (const auto& dev : inputs) {
        if (!Media::MediaUtils::isIrCamera(dev.description())) {
            device = dev;
            break;
        }
    }
    if (device.isNull()) device = QMediaDevices::defaultVideoInput();
    if (device.isNull()) {
        if (error) *error = QStringLiteral("no_camera");
        return false;
    }
    QCameraFormat bestFormat;
    int bestScore = std::numeric_limits<int>::max();
    const auto formatRank = [](QVideoFrameFormat::PixelFormat pf) -> int {
        switch (pf) {
        case QVideoFrameFormat::Format_YUV420P: return 0;
        case QVideoFrameFormat::Format_NV12: return 1;
        case QVideoFrameFormat::Format_YUYV: return 2;
        case QVideoFrameFormat::Format_UYVY: return 3;
        default: return 10;
        }
    };
    for (const QCameraFormat& fmt : device.videoFormats()) {
        const QSize res = fmt.resolution();
        const int w = res.width();
        const int h = res.height();
        if (w <= 0 || h <= 0 || w > 1280 || h > 720) continue;
        const int areaDiff = std::abs(w * h - 640 * 360);
        const int score = formatRank(fmt.pixelFormat()) * 500000 + areaDiff;
        if (score < bestScore) {
            bestScore = score;
            bestFormat = fmt;
        }
    }
    m_camera = new QCamera(device, this);
    if (!bestFormat.isNull()) m_camera->setCameraFormat(bestFormat);
    m_capture = new QMediaCaptureSession(this);
    m_sink = new QVideoSink(this);
    m_capture->setCamera(m_camera);
    m_capture->setVideoSink(m_sink);

    m_encodeThread = new QThread(this);
    m_encodeThread->setObjectName(QStringLiteral("zalos-cam-enc"));
    m_encodeWorker = new QObject;
    m_encodeWorker->moveToThread(m_encodeThread);
    connect(m_encodeThread, &QThread::finished, m_encodeWorker, &QObject::deleteLater);
    m_encodeBusy.store(false);
    m_encodeThread->start();

    connect(m_sink, &QVideoSink::videoFrameChanged, this, [this](const QVideoFrame& frame) {
        if (!frame.isValid()) return;
        if (m_preview) m_preview->setVideoFrame(frame);
        if (!m_encodingEnabled.load()) return;
        const qint64 now = m_clock.elapsed();
        int fps = 15;
        {
            QMutexLocker lock(&m_stateMutex);
            fps = m_fps;
        }
        if (m_lastFrameMs >= 0 && now - m_lastFrameMs < 1000 / fps - 2) return;
        if (m_encodeBusy.exchange(true)) return;
        m_lastFrameMs = now;
        if (!m_encodeWorker) {
            m_encodeBusy.store(false);
            return;
        }
        QMetaObject::invokeMethod(m_encodeWorker, [this, frame, now]() {
            encodeFrame(frame, now);
            m_encodeBusy.store(false);
        }, Qt::QueuedConnection);
    });
    connect(m_camera, &QCamera::errorOccurred, this, [this](QCamera::Error err, const QString& text) {
        if (err == QCamera::NoError) return;
        const QString reason = text.isEmpty() ? QStringLiteral("camera_error") : text;
        stop();
        emit failed(reason);
    });
    m_forceKey.store(true);
    {
        QMutexLocker lock(&m_stateMutex);
        m_reopen = true;
    }
    m_lastFrameMs = -1;
    m_camera->start();
    return true;
}

void CameraSender::stop() {
    if (m_sink) disconnect(m_sink, nullptr, this, nullptr);
    if (m_camera) {
        disconnect(m_camera, nullptr, this, nullptr);
        m_camera->stop();
    }
    if (m_encodeThread) {
        m_encodeThread->quit();
        m_encodeThread->wait();
        m_encodeThread->deleteLater();
        m_encodeThread = nullptr;
        m_encodeWorker = nullptr;
    }
    m_encodeBusy.store(false);
    if (m_capture) m_capture->deleteLater();
    m_capture = nullptr;
    if (m_camera) m_camera->deleteLater();
    m_camera = nullptr;
    if (m_sink) m_sink->deleteLater();
    m_sink = nullptr;
    m_encoder.close();
    if (m_preview) m_preview->setVideoFrame(QVideoFrame());
}

void CameraSender::setProfile(QSize size, int fps, int bitrate) {
    size = QSize(size.width() & ~1, size.height() & ~1);
    if (size.width() < 16 || size.height() < 16) return;
    fps = qBound(1, fps, 30);
    bitrate = qBound(30000, bitrate, 4000000);
    QMutexLocker lock(&m_stateMutex);
    if (size == m_size && fps == m_fps && bitrate == m_bitrate) return;
    m_size = size;
    m_fps = fps;
    m_bitrate = bitrate;
    m_reopen = true;
}

void CameraSender::setEncodingEnabled(bool enabled) {
    const bool prev = m_encodingEnabled.exchange(enabled);
    if (enabled && !prev) m_forceKey.store(true);
}

void CameraSender::processFrame(const QVideoFrame& frame) {
    if (!frame.isValid()) return;
    if (m_preview) m_preview->setVideoFrame(frame);
    if (!m_encodingEnabled.load()) return;
    const qint64 now = m_clock.elapsed();
    int fps = 15;
    {
        QMutexLocker lock(&m_stateMutex);
        fps = m_fps;
    }
    if (m_lastFrameMs >= 0 && now - m_lastFrameMs < 1000 / fps - 2) return;
    m_lastFrameMs = now;
    encodeFrame(frame, now);
}

void CameraSender::encodeFrame(const QVideoFrame& frame, qint64 now) {
    QSize targetSize;
    int fps = 15;
    int bitrate = 300000;
    bool needReopen = false;
    {
        QMutexLocker lock(&m_stateMutex);
        targetSize = m_size;
        fps = m_fps;
        bitrate = m_bitrate;
        needReopen = m_reopen;
        m_reopen = false;
    }
    if (needReopen || !m_encoder.isOpen()) {
        if (!m_encoder.open(targetSize, fps, bitrate)) {
            emit failed(QStringLiteral("encoder_open"));
            return;
        }
        m_forceKey.store(true);
    }
    const QByteArray i420 = frameToI420(frame, targetSize);
    if (i420.isEmpty()) return;
    if (m_lastKeyMs < 0 || now - m_lastKeyMs >= kKeyIntervalMs) m_forceKey.store(true);
    bool key = false;
    const QByteArray au = m_encoder.encodeI420(i420, now, m_forceKey.load(), &key);
    if (au.isEmpty()) return;
    if (key) {
        m_forceKey.store(false);
        m_lastKeyMs = now;
    }
    emit frameEncoded(key, au, targetSize.width(), targetSize.height());
}

}
