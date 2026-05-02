using System;
using UnityEngine;
using VContainer;
using DG.Tweening;

namespace Features.InGame
{
    public class InGameEmotionPopupView : MonoBehaviour
    {
        [SerializeField] private RectTransform m_popupRoot;

        private IEmotionPopupViewModel m_viewModel;

        [Inject]
        public void Construct(IEmotionPopupViewModel viewModel)
        {
            m_viewModel = viewModel;
            m_viewModel.OnShowEmotion += PlayEmotionEffect;
            
            if (m_popupRoot != null)
            {
                m_popupRoot.gameObject.SetActive(false);
            }
        }

        private void PlayEmotionEffect(string key)
        {
            if (m_popupRoot == null)
            {
                return;
            }

            Debug.Log($"[InGameEmotionPopupView] 감정 연출: {key}");
            m_popupRoot.gameObject.SetActive(true);
            m_popupRoot.localScale = Vector3.zero;
            
            m_popupRoot.DOScale(1.2f, 0.3f).SetEase(Ease.OutBack).OnComplete(() => {
                m_popupRoot.DOScale(1.0f, 0.1f).OnComplete(() => {
                    m_popupRoot.DOScale(0, 0.2f).SetDelay(1.0f).OnComplete(() => {
                        m_popupRoot.gameObject.SetActive(false);
                    });
                });
            });
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnShowEmotion -= PlayEmotionEffect;
            }
        }
    }
}
