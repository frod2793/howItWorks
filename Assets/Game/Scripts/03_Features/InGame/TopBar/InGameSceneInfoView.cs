using UnityEngine;
using TMPro;
using UnityEngine.UI;
using VContainer;

namespace Features.InGame
{
    public class InGameSceneInfoView : MonoBehaviour
    {
        [Header("UI 텍스트 구성요소")]
        [SerializeField] private TextMeshProUGUI m_sceneTitleText;
        [SerializeField] private TextMeshProUGUI m_locationText;
        [SerializeField] private TextMeshProUGUI m_playthroughText;
        [SerializeField] private Button m_menuButton;

        private ISceneInfoViewModel m_viewModel;
        private ISoundService m_soundService;

        [Inject]
        public void Construct(ISceneInfoViewModel viewModel, ISoundService soundService = null)
        {
            m_viewModel = viewModel;
            m_viewModel.OnSceneInfoUpdated += UpdateSceneInfo;
            m_soundService = soundService;
        }

        private void Start()
        {
            if (m_menuButton != null)
            {
                m_menuButton.onClick.RemoveAllListeners();
                m_menuButton.onClick.AddListener(func_OnSettingsButtonClicked);
            }

            if (m_sceneTitleText != null)
            {
                m_sceneTitleText.text = "승(承) · 씬 8 — 카토 위기";
            }

            if (m_locationText != null)
            {
                m_locationText.text = "야만인 구역 외곽 · 밤";
            }

            if (m_playthroughText != null)
            {
                m_playthroughText.text = "1회차";
            }
        }

        private void UpdateSceneInfo()
        {
            if (m_viewModel == null)
            {
                return;
            }

            if (m_sceneTitleText != null)
            {
                m_sceneTitleText.text = m_viewModel.DisplaySceneTitle;
            }

            if (m_locationText != null)
            {
                m_locationText.text = m_viewModel.DisplayLocation;
            }

            if (m_playthroughText != null)
            {
                m_playthroughText.text = m_viewModel.DisplayPlaythrough;
            }
        }

        public void func_OnSettingsButtonClicked()
        {
            if (m_soundService != null)
            {
                m_soundService.PlaySFX(SoundKeys.Click);
            }

            if (m_viewModel != null)
            {
                m_viewModel.RequestSettings();
            }
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnSceneInfoUpdated -= UpdateSceneInfo;
            }
        }
    }
}
