using UnityEngine;
using UnityEngine.UI;
using TMPro;
using Domain.InGame;
using VContainer;

namespace Features.InGame
{
    public class InGameTopBarView : MonoBehaviour
    {
        [Header("상태 UI")]
        [SerializeField] private TextMeshProUGUI m_sceneBadgeText;
        [SerializeField] private TextMeshProUGUI m_locationText;
        [SerializeField] private TextMeshProUGUI m_dayText;
        [SerializeField] private TextMeshProUGUI m_playthroughText;

        [Header("제어 요소")]
        [SerializeField] private Button m_menuButton;

        private ITopBarViewModel m_viewModel;

        [Inject]
        public void Construct(ITopBarViewModel viewModel)
        {
            m_viewModel = viewModel;
            m_viewModel.OnStatsChanged += UpdateUI;

            if (m_menuButton != null)
            {
                m_menuButton.onClick.AddListener(() =>
                {
                    m_viewModel.ClickMenu();
                });
            }
        }

        private void UpdateUI(PlayerStatsDTO stats)
        {
            if (m_sceneBadgeText != null)
            {
                m_sceneBadgeText.text = $"SCENE {stats.SceneNumber:D2}";
            }
            if (m_locationText != null)
            {
                m_locationText.text = stats.CurrentLocation;
            }
            if (m_dayText != null)
            {
                m_dayText.text = $"Day {stats.Day}";
            }
            if (m_playthroughText != null)
            {
                m_playthroughText.text = $"{stats.Playthrough}회차";
            }
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnStatsChanged -= UpdateUI;
            }
            if (m_menuButton != null)
            {
                m_menuButton.onClick.RemoveAllListeners();
            }
        }
    }
}
