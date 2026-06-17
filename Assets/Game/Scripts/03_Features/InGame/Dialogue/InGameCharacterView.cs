using UnityEngine;
using UnityEngine.UI;
using VContainer;
using Domain.InGame;
using DG.Tweening;

namespace Features.InGame
{
    public class InGameCharacterView : MonoBehaviour
    {
        [Header("캐릭터 일러스트 위치 (좌/중/우)")]
        [SerializeField] private Image m_leftCharacterImage;
        [SerializeField] private Image m_centerCharacterImage;
        [SerializeField] private Image m_rightCharacterImage;

        private IDialogueViewModel m_viewModel;

        [Inject]
        public void Construct(IDialogueViewModel viewModel)
        {
            m_viewModel = viewModel;
            m_viewModel.OnDialogueUpdated += UpdateCharacterIllustration;
        }

        private void UpdateCharacterIllustration(DialogueDTO dialogue)
        {
            // 임시 구현: 발화자 이름에 따라 일러스트 변경 연출 (추후 확장)
            if (dialogue.Type == DialogueType.Normal)
            {
                // 실제 구현 시 캐릭터 스프라이트를 로드하고 DOTween으로 페이드인/아웃 연출
                // m_centerCharacterImage.sprite = ...
            }
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnDialogueUpdated -= UpdateCharacterIllustration;
            }
        }
    }
}
