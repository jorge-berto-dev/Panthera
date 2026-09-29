/* calamares/branding/panthera/show.qml - slideshow T5 (ODT Secao 11: Leve, Privado, Seu) */
import QtQuick 2.0
import calamares.slideshow 1.0

Presentation {
    id: presentation
    Timer {
        interval: 8000
        running: true
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }
    Slide {
        /* Slide 1: Leve */
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            color: "#0B111C"
            Text {
                anchors.centerIn: parent
                text: "LEVE\nSeu PC antigo voando"
                color: "#F3F6F9"
                font.family: "Inter"
                font.pointSize: 22
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
    Slide {
        /* Slide 2: Privado */
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            color: "#141B2B"
            Text {
                anchors.centerIn: parent
                text: "PRIVADO\nSeus dados só seus"
                color: "#1D83FF"
                font.family: "Inter"
                font.pointSize: 22
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
    Slide {
        /* Slide 3: Seu */
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            color: "#0B111C"
            Text {
                anchors.centerIn: parent
                text: "SEU\nLiberdade para o seu mundo"
                color: "#8490A4"
                font.family: "Inter"
                font.pointSize: 22
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
