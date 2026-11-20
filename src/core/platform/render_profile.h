#pragma once

#include <QString>

namespace Zalos::Core::Platform {

struct RenderProfile {
    enum class Backend { Default, Vulkan, OpenGL, Software };
    Backend backend{Backend::Default};
    bool basicRenderLoop{false};
    bool fromOverride{false};
    QString reason;

    struct Inputs {
        bool hasRenderNode{false};
        QString gpuVendor;
        bool mesaVulkanIcd{false};
        bool qtHasVulkan{false};
        bool vulkanFailedBefore{false};
        bool hardwareAcceleration{false};
        QString hardwareFailed;
        qint64 memTotalKb{0};
        int cpuCores{0};
        QString override;
    };

    static RenderProfile decide(const Inputs& in);
    static Inputs probeSystem();
    static QString backendName(Backend b);
    static Backend backendFromName(const QString& name);

    bool guarded() const { return backend != Backend::Software && !fromOverride; }
    void apply() const;
};

namespace RenderGuard {
bool vulkanFailedBefore();
void markAttempt(RenderProfile::Backend backend);
void markFirstFrame();
void recordFailure(RenderProfile::Backend backend);
QString lastFailure();
bool hardwareAccelerationEnabled();
void setHardwareAccelerationEnabled(bool enabled);
}

}
