import QtQuick
import QtMultimedia

Item {
    id: root
    property int fillMode: VideoOutput.PreserveAspectFit
    property alias output: out
    readonly property QtObject videoSink: out.videoSink

    VideoOutput {
        id: out
        anchors.fill: parent
        fillMode: root.fillMode
    }
}
