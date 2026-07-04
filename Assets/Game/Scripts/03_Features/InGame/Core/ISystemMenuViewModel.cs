using System;
using Domain.InGame;

namespace Features.InGame
{
    /// <summary>
    /// [기능]: 시스템 메뉴의 UI 상태 관리 및 사용자 행동 명령을 정의하는 뷰모델 인터페이스입니다.
    /// [작성자]: 윤승종
    /// </summary>
    public interface ISystemMenuViewModel
    {
        #region 이벤트 (Events)
        event Action<SceneInfoDTO> OnSceneInfoUpdated;
        event Action OnResumeRequested;
        event Action OnSaveLoadRequested;
        event Action OnSettingsRequested;
        event Action OnArchiveRequested;
        event Action OnEncyclopediaRequested;
        event Action OnTitleRequested;
        event Action OnExitRequested;
        #endregion

        #region 프로퍼티 (Properties)
        SceneInfoDTO CurrentSceneInfo { get; }
        string DisplayLocationSummary { get; }
        #endregion

        #region 비즈니스 로직 메서드 (Methods)
        void SetSceneInfo(SceneInfoDTO info);
        void Resume();
        void OpenSaveLoad();
        void OpenSettings();
        void OpenArchive();
        void OpenEncyclopedia();
        void ConfirmReturnToTitle();
        void ConfirmExitGame();
        #endregion
    }
}
