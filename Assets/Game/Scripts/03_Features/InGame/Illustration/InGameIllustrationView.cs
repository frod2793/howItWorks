using UnityEngine;
using UnityEngine.UI;
using VContainer;
using DG.Tweening;

namespace Features.InGame
{
    public class InGameIllustrationView : MonoBehaviour
    {
        [Header("이미지 레이어")]
        [SerializeField] private Image m_characterImage;
        [SerializeField] private Image m_backgroundImage;
        [SerializeField] private Image m_toneOverlayImage;

        private IIllustrationViewModel m_viewModel;

        [Inject]
        public void Construct(IIllustrationViewModel viewModel)
        {
            m_viewModel = viewModel;
            m_viewModel.OnCharacterChanged += UpdateCharacter;
            m_viewModel.OnBackgroundChanged += UpdateBackground;
            m_viewModel.OnToneChanged += UpdateTone;
        }

        private void UpdateCharacter(string key)
        {
            Debug.Log($"[InGameIllustrationView] 캐릭터 변경: {key}");
            if (m_characterImage != null)
            {
                m_characterImage.DOFade(0, 0.2f).OnComplete(() =>
                {
                    m_characterImage.DOFade(1, 0.2f);
                });
            }
        }

        private void UpdateBackground(string key)
        {
            Debug.Log($"[InGameIllustrationView] 배경 변경: {key}");
            if (m_backgroundImage != null)
            {
                m_backgroundImage.DOFade(0, 0.3f).OnComplete(() =>
                {
                    m_backgroundImage.DOFade(1, 0.3f);
                });
            }
        }

        private void UpdateTone(Color color)
        {
            Debug.Log($"[InGameIllustrationView] 색조 변경: {color}");
            if (m_toneOverlayImage != null)
            {
                m_toneOverlayImage.DOColor(color, 0.5f);
            }
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnCharacterChanged -= UpdateCharacter;
                m_viewModel.OnBackgroundChanged -= UpdateBackground;
                m_viewModel.OnToneChanged -= UpdateTone;
            }
        }
    }
}
