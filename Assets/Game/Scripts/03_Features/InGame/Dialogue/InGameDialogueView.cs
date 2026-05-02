using UnityEngine;
using UnityEngine.UI;
using TMPro;
using VContainer;
using Cysharp.Threading.Tasks;
using Domain.InGame;

namespace Features.InGame
{
    public class InGameDialogueView : MonoBehaviour
    {
        [Header("UI 구성 요소")]
        [SerializeField] private Image m_backgroundImage;
        [SerializeField] private Image m_speakerIcon;
        [SerializeField] private TextMeshProUGUI m_nameText;
        [SerializeField] private TextMeshProUGUI m_contentText;
        [SerializeField] private Button m_nextButton;
        [SerializeField] private TypewriterEffect m_typewriterEffect;

        private IDialogueViewModel m_viewModel;

        [Inject]
        public void Construct(IDialogueViewModel viewModel)
        {
            m_viewModel = viewModel;
            m_viewModel.OnDialogueUpdated += UpdateDialogue;

            if (m_backgroundImage != null)
            {
                Color color = m_backgroundImage.color;
                color.a = 0.85f;
                m_backgroundImage.color = color;
            }

            if (m_nextButton != null)
            {
                m_nextButton.onClick.AddListener(() =>
                {
                    m_viewModel.RequestNext();
                });
            }
        }

        private void UpdateDialogue(DialogueDTO dialogue)
        {
            if (m_nameText != null)
            {
                m_nameText.text = dialogue.SpeakerName;
            }
            
            if (m_speakerIcon != null)
            {
                if (string.IsNullOrEmpty(dialogue.SpeakerIconKey))
                {
                    m_speakerIcon.gameObject.SetActive(false);
                }
                else
                {
                    m_speakerIcon.gameObject.SetActive(true);
                    // TODO: ResourceLoader를 통한 아이콘 교체 로직
                }
            }

            if (m_typewriterEffect != null && m_contentText != null)
            {
                m_typewriterEffect.Play(m_contentText, dialogue.Content).Forget();
            }
            else if (m_contentText != null)
            {
                m_contentText.text = dialogue.Content;
            }
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnDialogueUpdated -= UpdateDialogue;
            }
            if (m_nextButton != null)
            {
                m_nextButton.onClick.RemoveAllListeners();
            }
        }
    }
}
