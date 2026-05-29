using UnityEngine;
using UnityEngine.UI;
using VContainer;

namespace Features.InGame
{
    public class InGameQuickMenuView : MonoBehaviour
    {
        private IQuickMenuViewModel m_viewModel;

        [Inject]
        public void Construct(IQuickMenuViewModel viewModel)
        {
            m_viewModel = viewModel;

            m_viewModel.OnAutoToggled += (isOn) =>
            {
                Debug.Log($"[QuickMenu] 자동 재생 상태: {isOn}");
            };

            m_viewModel.OnSkipToggled += (isOn) =>
            {
                Debug.Log($"[QuickMenu] 스킵 상태: {isOn}");
            };
        }

        public void func_OnSaveButtonClicked()
        {
            if (m_viewModel != null)
            {
                m_viewModel.RequestSave();
            }
        }

        public void func_OnLoadButtonClicked()
        {
            if (m_viewModel != null)
            {
                m_viewModel.RequestLoad();
            }
        }

        public void func_OnLogButtonClicked()
        {
            if (m_viewModel != null)
            {
                m_viewModel.RequestLog();
            }
        }

        public void func_OnAutoButtonClicked()
        {
            if (m_viewModel != null)
            {
                m_viewModel.ClickAuto();
            }
        }

        public void func_OnSkipButtonClicked()
        {
            if (m_viewModel != null)
            {
                m_viewModel.ClickSkip();
            }
        }

        public void func_OnMenuButtonClicked()
        {
            if (m_viewModel != null)
            {
                m_viewModel.RequestMenu();
            }
        }
    }
}
