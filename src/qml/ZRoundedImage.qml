import QtQuick
import QtQuick.Window
import Zalos
import "MediaSource.js" as MediaSource

Item {
    id: root
    readonly property bool windowShowing: Window.window ? (Window.window.visible && Window.window.visibility !== Window.Minimized) : true
    property url source: ""
    readonly property bool animReady: animLoader.item !== null && animLoader.item.status === Image.Ready
    readonly property int status: root.animReady ? Image.Ready : img.status
    property alias sourceSize: img.sourceSize
    property alias fillMode: img.fillMode
    readonly property real implicitImageWidth: (root.animReady && animLoader.item.implicitWidth > 0)
                                               ? animLoader.item.implicitWidth : img.implicitWidth
    readonly property real implicitImageHeight: (root.animReady && animLoader.item.implicitHeight > 0)
                                                ? animLoader.item.implicitHeight : img.implicitHeight
    property url animatedSource: ""
    property real radius: 8
    property bool topOnly: false
    property bool cache: true
    readonly property bool gpu: GraphicsInfo.api !== GraphicsInfo.Software
    readonly property bool masked: gpu && maskLoader.status === Loader.Ready

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.mediaPlaceholder
        visible: img.status !== Image.Ready && !root.animReady
    }
    Item {
        id: content
        anchors.fill: parent
        Image {
            id: img
            anchors.fill: parent
            source: MediaSource.toSource(root.source)
            asynchronous: true
            cache: root.cache
            smooth: true
            fillMode: Image.PreserveAspectCrop
            visible: !root.animReady
        }
        Loader {
            id: animLoader
            anchors.fill: parent
            active: root.animatedSource.toString().length > 0
            sourceComponent: AnimatedImage {
                source: root.animatedSource
                cache: false
                smooth: true
                fillMode: img.fillMode
                playing: status === Image.Ready && root.visible && root.windowShowing
                visible: status === Image.Ready
            }
        }
    }
    ShaderEffectSource {
        id: contentLayer
        anchors.fill: content
        sourceItem: root.masked ? content : null
        hideSource: root.masked
        live: true
        visible: false
    }
    Item {
        id: maskShape
        anchors.fill: parent
        layer.enabled: root.masked
        visible: false
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            Rectangle {
                visible: root.topOnly
                anchors.bottom: parent.bottom
                width: parent.width
                height: root.radius
            }
        }
    }
    Loader {
        id: maskLoader
        anchors.fill: content
        active: root.gpu && root.radius > 0 && (img.status === Image.Ready || root.animReady)
        source: "ZMaskEffect.qml"
        onLoaded: {
            maskLoader.item.source = contentLayer;
            maskLoader.item.maskSource = maskShape;
        }
    }
}
