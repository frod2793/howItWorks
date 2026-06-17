using UnityEngine;
using TMPro;
using VContainer;
using Domain.InGame;

namespace Features.InGame
{
    public class InGameSceneInfoView : MonoBehaviour
    {
        [Header("UI 텍스트 구성요소")]
        [SerializeField] private TextMeshProUGUI m_sceneTitleText;
        [SerializeField] private TextMeshProUGUI m_locationText;
        [SerializeField] private TextMeshProUGUI m_playthroughText;
        [SerializeField] private UnityEngine.UI.Button m_menuButton;

        private ISceneInfoViewModel m_viewModel;

        [Inject]
        public void Construct(ISceneInfoViewModel viewModel)
        {
            m_viewModel = viewModel;
            m_viewModel.OnSceneInfoChanged += UpdateSceneInfo;
        }

        private void Start()
        {
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

        private void UpdateSceneInfo(SceneInfoDTO info)
        {
            if (m_sceneTitleText != null)
            {
                m_sceneTitleText.text = $"{info.ActName} · 씬 {info.SceneNumber} — {info.SceneTitle}";
            }

            if (m_locationText != null)
            {
                m_locationText.text = $"{info.Location} · {info.TimeOfDay}";
            }

            if (m_playthroughText != null)
            {
                m_playthroughText.text = $"{info.Playthrough}회차";
            }
        }

        public void func_OnSettingsButtonClicked()
        {
            // 설정/메뉴 팝업 호출 로직
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnSceneInfoChanged -= UpdateSceneInfo;
            }
        }
    }
}
