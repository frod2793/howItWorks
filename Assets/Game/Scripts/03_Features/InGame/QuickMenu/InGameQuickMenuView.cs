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

            // 상태 변경 이벤트 구독 (시각적 피드백 필요 시 활용)
            m_viewModel.OnAutoToggled += (isOn) =>
            {
                Debug.Log($"[QuickMenu] AUTO State: {isOn}");
                // TODO: 버튼 색상 변경 등 연출 추가 가능
            };

            m_viewModel.OnSkipToggled += (isOn) =>
            {
                Debug.Log($"[QuickMenu] SKIP State: {isOn}");
                // TODO: 버튼 색상 변경 등 연출 추가 가능
            };
        }

        public void func_OnSaveButtonClicked()
        {
            m_viewModel?.RequestSave();
        }

        public void func_OnLoadButtonClicked()
        {
            m_viewModel?.RequestLoad();
        }

        public void func_OnLogButtonClicked()
        {
            m_viewModel?.RequestLog();
        }

        public void func_OnAutoButtonClicked()
        {
            m_viewModel?.ClickAuto();
        }

        public void func_OnSkipButtonClicked()
        {
            m_viewModel?.ClickSkip();
        }

        public void func_OnMenuButtonClicked()
        {
            m_viewModel?.RequestMenu();
        }
    }
}
