using Toybox.Application;
using Toybox.WatchUi;

// 앱 진입점. manifest.xml 의 entry="zzPowerPlusApp" 와 일치해야 한다.
class zzPowerPlusApp extends Application.AppBase {

    hidden var mView = null;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
        if (mView != null) {
            mView.persist();
        }
    }

    function getInitialView() {
        mView = new zzPowerPlusView();
        return [ mView ];
    }

    // Connect IQ 앱 / Garmin Express 에서 설정 변경 시 호출
    function onSettingsChanged() {
        Config.invalidate();
        Zones.loadBounds();
        if (mView != null) {
            mView.onSettingsChanged();
        }
        WatchUi.requestUpdate();
    }
}
