using UnityEngine;
using VContainer;
using DG.Tweening;

namespace Features.InGame
{
    public class InGameUIVisibilityView : MonoBehaviour
    {
        [Header("가시성 설정")]
        [SerializeField] private CanvasGroup m_uiCanvasGroup;
        [SerializeField] private float m_fadeDuration = 0.2f;

        private IUIVisibilityViewModel m_viewModel;

        [Inject]
        public void Construct(IUIVisibilityViewModel viewModel)
        {
            m_viewModel = viewModel;
            m_viewModel.OnVisibilityChanged += HandleVisibilityChanged;
        }

        private void HandleVisibilityChanged(bool isVisible)
        {
            if (m_uiCanvasGroup == null)
            {
                return;
            }

            float targetAlpha = 1.0f;
            if (isVisible == false)
            {
                targetAlpha = 0.0f;
            }

            m_uiCanvasGroup.DOFade(targetAlpha, m_fadeDuration).OnComplete(() =>
            {
                m_uiCanvasGroup.interactable = isVisible;
                m_uiCanvasGroup.blocksRaycasts = isVisible;
            });
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnVisibilityChanged -= HandleVisibilityChanged;
            }
        }
    }
}
