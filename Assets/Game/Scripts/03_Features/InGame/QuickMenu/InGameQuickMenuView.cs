using UnityEngine;
using UnityEngine.UI;
using VContainer;

namespace Features.InGame
{
    public class InGameQuickMenuView : MonoBehaviour
    {
        [SerializeField] private Button m_settingsButton;
        [SerializeField] private Button m_logButton;
        [SerializeField] private Toggle m_autoToggle;
        [SerializeField] private Toggle m_skipToggle;

        private IQuickMenuViewModel m_viewModel;

        [Inject]
        public void Construct(IQuickMenuViewModel viewModel)
        {
            m_viewModel = viewModel;

            if (m_settingsButton != null)
            {
                m_settingsButton.onClick.AddListener(() =>
                {
                    m_viewModel.OpenSettings();
                });
            }
            if (m_logButton != null)
            {
                m_logButton.onClick.AddListener(() =>
                {
                    m_viewModel.OpenLog();
                });
            }
            if (m_autoToggle != null)
            {
                m_autoToggle.onValueChanged.AddListener((isOn) =>
                {
                    m_viewModel.ToggleAuto(isOn);
                });
            }
            if (m_skipToggle != null)
            {
                m_skipToggle.onValueChanged.AddListener((isOn) =>
                {
                    m_viewModel.ToggleSkip(isOn);
                });
            }
        }

        private void OnDestroy()
        {
            if (m_settingsButton != null)
            {
                m_settingsButton.onClick.RemoveAllListeners();
            }
            if (m_logButton != null)
            {
                m_logButton.onClick.RemoveAllListeners();
            }
            if (m_autoToggle != null)
            {
                m_autoToggle.onValueChanged.RemoveAllListeners();
            }
            if (m_skipToggle != null)
            {
                m_skipToggle.onValueChanged.RemoveAllListeners();
            }
        }
    }
}
