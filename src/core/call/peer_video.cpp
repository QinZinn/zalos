#include "peer_video.h"

#include "h264_codec.h"

namespace Zalos::Core::Call {

PeerVideoDecoder::PeerVideoDecoder(QObject* parent) : QObject(parent) {}

PeerVideoDecoder::~PeerVideoDecoder() = default;

void PeerVideoDecoder::decode(bool isKey, const QString& codec, const QByteArray& data, int src) {
    Q_UNUSED(codec);
    struct PendingGuard {
        std::atomic<int>* counter{nullptr};
        ~PendingGuard() {
            if (counter) {
                int cur = counter->load(std::memory_order_relaxed);
                while (cur > 0 && !counter->compare_exchange_weak(cur, cur - 1, std::memory_order_relaxed)) {}
            }
        }
    } guard{m_pendingCounter};
    if (m_streams.size() >= 16 && m_streams.find(src) == m_streams.end()) {
        m_streams.erase(m_streams.begin());
    }
    Stream& stream = m_streams[src];
    if (!stream.decoder) {
        if (!isKey) {
            if (!stream.waitingForKey) {
                stream.waitingForKey = true;
                emit keyFrameNeeded(QStringLiteral("start"), src);
            }
            return;
        }
        stream.decoder = std::make_unique<H264Decoder>();
        if (!stream.decoder->isOpen()) {
            stream.decoder.reset();
            return;
        }
    }
    stream.waitingForKey = false;
    bool damaged = false;
    const QVideoFrame frame = stream.decoder->decode(data, &damaged);
    if (damaged) emit keyFrameNeeded(QStringLiteral("decode"), src);
    if (frame.isValid()) emit frameDecoded(frame, src);
}

void PeerVideoDecoder::reset() {
    m_streams.clear();
    if (m_pendingCounter) m_pendingCounter->store(0, std::memory_order_relaxed);
}

}
