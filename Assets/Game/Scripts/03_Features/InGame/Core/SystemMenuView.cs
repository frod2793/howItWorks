using System;
using Cysharp.Threading.Tasks;
using DG.Tweening;
using Domain.InGame;
using TMPro;
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.InputSystem;

namespace Features.InGame
{
    /// <summary>
    /// [기능]: 시스템 메뉴의 UI 렌더링, 페이드 애니메이션 및 사용자 클릭 이벤트를 바인딩하는 뷰 클래스입니다.
    /// [작성자]: 윤승종
    /// </summary>
    public class SystemMenuView : MonoBehaviour
    {
        #region UI 참조 (Inspector)
        [Header("오버레이 제어")]
        [SerializeField] private Canvas m_canvas;
        [SerializeField] private CanvasGroup m_canvasGroup;
        [SerializeField] private GameObject m_menuContainer;
        [SerializeField] private Button m_backgroundDimButton;

        [Header("정보 표시 영역")]
        [SerializeField] private TMP_Text m_locationSummaryText;

        [Header("시스템 메뉴 7종 버튼")]
        [SerializeField] private Button m_resumeButton;
        [SerializeField] private Button m_saveLoadButton;
        [SerializeField] private Button m_settingsButton;
        [SerializeField] private Button m_archiveButton;
        [SerializeField] private Button m_encyclopediaButton;
        [SerializeField] private Button m_titleButton;
        [SerializeField] private Button m_exitButton;
        #endregion

        #region 내부 필드 (Private Fields)
        private ISystemMenuViewModel m_viewModel;
        private ISoundService m_soundService;
        private bool m_isOpen;
        private float m_cachedOriginalBgmVolume = 1.0f;
        #endregion

        #region 초기화 (Initialization)
        /// <summary>
        /// [기능]: 외부 DI 컨테이너를 통해 시스템 메뉴 뷰모델 및 사운드 서비스를 주입받아 초기화합니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-04
        /// </summary>
        public void Initialize(ISystemMenuViewModel viewModel, ISoundService soundService)
        {
            m_viewModel = viewModel;
            m_soundService = soundService;

            m_viewModel.OnSceneInfoUpdated += UpdateLocationSummary;

            // 버튼 클릭 리스너 연결 (Allman 스타일)
            m_resumeButton.onClick.AddListener(func_OnResumeClick);
            m_saveLoadButton.onClick.AddListener(func_OnSaveLoadClick);
            m_settingsButton.onClick.AddListener(func_OnSettingsClick);
            m_archiveButton.onClick.AddListener(func_OnArchiveClick);
            m_encyclopediaButton.onClick.AddListener(func_OnEncyclopediaClick);
            m_titleButton.onClick.AddListener(func_OnTitleClick);
            m_exitButton.onClick.AddListener(func_OnExitClick);
            
            if (m_backgroundDimButton != null)
            {
                m_backgroundDimButton.onClick.AddListener(func_OnBackgroundClick);
            }

            // 초기 상태: 꺼진 상태
            m_canvasGroup.alpha = 0f;
            m_canvasGroup.blocksRaycasts = false;
            
            if (m_canvas != null)
            {
                m_canvas.enabled = false;
            }
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnSceneInfoUpdated -= UpdateLocationSummary;
            }
        }
        #endregion

        #region UI Event Callbacks (func_ 접두사 규칙 적용)
        public void func_OnResumeClick()
        {
            if (m_viewModel != null)
            {
                m_viewModel.Resume();
            }
        }

        public void func_OnSaveLoadClick()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OpenSaveLoad();
            }
        }

        public void func_OnSettingsClick()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OpenSettings();
            }
        }

        public void func_OnArchiveClick()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OpenArchive();
            }
        }

        public void func_OnEncyclopediaClick()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OpenEncyclopedia();
            }
        }

        public void func_OnTitleClick()
        {
            if (m_viewModel != null)
            {
                m_viewModel.ConfirmReturnToTitle();
            }
        }

        public void func_OnExitClick()
        {
            if (m_viewModel != null)
            {
                m_viewModel.ConfirmExitGame();
            }
        }

        public void func_OnBackgroundClick()
        {
            func_Close();
        }
        #endregion

        #region 유니티 생명주기 (Unity Lifecycle)
        private void Update()
        {
            if (m_isOpen == false)
            {
                return;
            }

            var keyboard = Keyboard.current;
            if (keyboard == null)
            {
                return;
            }

            // Esc 단축키 입력으로 닫기 처리 (Input System Package 대응)
            if (keyboard.escapeKey.wasPressedThisFrame)
            {
                func_Close();
            }
        }
        #endregion

        #region 공개 메서드 (Public Methods)
        /// <summary>
        /// [기능]: 140ms 페이드인 효과와 함께 BGM을 덕킹하며 시스템 메뉴를 엽니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-04
        /// </summary>
        public void func_Open()
        {
            if (m_isOpen)
            {
                return;
            }

            m_isOpen = true;
            if (m_canvas != null)
            {
                m_canvas.enabled = true;
            }
            
            // 키보드/게임패드 내비게이션 대응 첫 번째 포커스 지정
            if (m_resumeButton != null)
            {
                m_resumeButton.Select();
            }

            m_canvasGroup.DOKill();
            m_canvasGroup.DOFade(1f, 0.14f)
                .SetUpdate(true)
                .OnComplete(() =>
                {
                    m_canvasGroup.blocksRaycasts = true;
                });

            // BGM 덕킹 실시 (현재 설정된 BGM 볼륨의 50%로 설정)
            if (m_soundService != null)
            {
                m_cachedOriginalBgmVolume = m_soundService.BGMVolume;
                m_soundService.SetBGMVolume(m_cachedOriginalBgmVolume * 0.5f);
            }

            Debug.Log("[SystemMenuView] 시스템 메뉴 패널 오픈 및 BGM -6dB 덕킹 실행.");
        }

        /// <summary>
        /// [기능]: 140ms 페이드아웃 효과와 BGM 복원 과정을 거쳐 시스템 메뉴를 닫습니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-04
        /// </summary>
        public void func_Close()
        {
            if (m_isOpen == false)
            {
                return;
            }

            m_isOpen = false;
            m_canvasGroup.blocksRaycasts = false;

            m_canvasGroup.DOKill();
            m_canvasGroup.DOFade(0f, 0.14f)
                .SetUpdate(true)
                .OnComplete(() =>
                {
                    if (m_canvas != null)
                    {
                        m_canvas.enabled = false;
                    }
                });

            // BGM 볼륨 원복
            if (m_soundService != null)
            {
                m_soundService.SetBGMVolume(m_cachedOriginalBgmVolume);
            }

            Debug.Log("[SystemMenuView] 시스템 메뉴 패널 닫기 및 BGM 볼륨 원복.");
        }
        #endregion

        #region 내부 헬퍼 (Private Helpers)
        private void UpdateLocationSummary(SceneInfoDTO info)
        {
            if (m_locationSummaryText != null && m_viewModel != null)
            {
                m_locationSummaryText.text = m_viewModel.DisplayLocationSummary;
            }
        }
        #endregion
    }
}
