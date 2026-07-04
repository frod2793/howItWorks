using System;
using Domain.InGame;
using UnityEngine;

namespace Features.InGame
{
    /// <summary>
    /// [기능]: 시스템 메뉴의 비즈니스 로직과 화면 상태 가공을 구현한 뷰모델 클래스입니다.
    /// [작성자]: 윤승종
    /// </summary>
    public class SystemMenuViewModel : ISystemMenuViewModel
    {
        #region 이벤트 (Events)
        public event Action<SceneInfoDTO> OnSceneInfoUpdated;
        public event Action OnResumeRequested;
        public event Action OnSaveLoadRequested;
        public event Action OnSettingsRequested;
        public event Action OnArchiveRequested;
        public event Action OnEncyclopediaRequested;
        public event Action OnTitleRequested;
        public event Action OnExitRequested;
        #endregion

        #region 내부 필드 (Private Fields)
        private readonly ISoundService m_soundService;
        private SceneInfoDTO m_currentSceneInfo;
        #endregion

        #region 프로퍼티 (Properties)
        public SceneInfoDTO CurrentSceneInfo
        {
            get
            {
                return m_currentSceneInfo;
            }
        }

        public string DisplayLocationSummary { get; private set; } = string.Empty;
        #endregion

        #region 초기화 (Initialization)
        public SystemMenuViewModel(ISoundService soundService)
        {
            m_soundService = soundService;
        }
        #endregion

        #region 공개 메서드 (Public Methods)
        /// <summary>
        /// [기능]: 현재 인게임 씬 정보를 기반으로 위치 및 요약 텍스트를 업데이트합니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-04
        /// </summary>
        public void SetSceneInfo(SceneInfoDTO info)
        {
            if (info != null)
            {
                m_currentSceneInfo = info;
                DisplayLocationSummary = $"현재 위치 — {info.ActName} · 씬 {info.SceneNumber} · {info.Playthrough}회차";
            }
            else
            {
                DisplayLocationSummary = "현재 위치 정보 없음";
            }

            if (OnSceneInfoUpdated != null)
            {
                OnSceneInfoUpdated.Invoke(m_currentSceneInfo);
            }
        }

        public void Resume()
        {
            PlayClickSound();
            if (OnResumeRequested != null)
            {
                OnResumeRequested.Invoke();
            }
        }

        public void OpenSaveLoad()
        {
            PlayClickSound();
            if (OnSaveLoadRequested != null)
            {
                OnSaveLoadRequested.Invoke();
            }
        }

        public void OpenSettings()
        {
            PlayClickSound();
            if (OnSettingsRequested != null)
            {
                OnSettingsRequested.Invoke();
            }
        }

        public void OpenArchive()
        {
            PlayClickSound();
            if (OnArchiveRequested != null)
            {
                OnArchiveRequested.Invoke();
            }
        }

        public void OpenEncyclopedia()
        {
            PlayClickSound();
            if (OnEncyclopediaRequested != null)
            {
                OnEncyclopediaRequested.Invoke();
            }
        }

        public void ConfirmReturnToTitle()
        {
            PlayClickSound();
            if (OnTitleRequested != null)
            {
                OnTitleRequested.Invoke();
            }
        }

        public void ConfirmExitGame()
        {
            PlayClickSound();
            if (OnExitRequested != null)
            {
                OnExitRequested.Invoke();
            }
        }
        #endregion

        #region 내부 헬퍼 (Private Helpers)
        private void PlayClickSound()
        {
            if (m_soundService != null)
            {
                m_soundService.PlaySFX(SoundKeys.Click);
            }
        }
        #endregion
    }
}
