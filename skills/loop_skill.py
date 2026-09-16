"""
self_loop_orchestrator_skill - 自循环编排
"""
import os
import sys
import yaml
import json
from datetime import datetime

# 添加项目根到 path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from skills.docx_skill import DocxGeneratorSkill
from skills.pptx_skill import PptxGeneratorSkill
from skills.evaluator_skill import QualityEvaluatorSkill
from skills.local_bridge_skill import LocalBridgeSkill

class SelfLoopOrchestratorSkill:
    def __init__(self, config_path="orchestrator/config.yaml"):
        self.config_path = config_path
        self.config = self._load_config()
        
        self.docx_skill = DocxGeneratorSkill(output_dir=self.config.get("output_dir", "output"))
        self.pptx_skill = PptxGeneratorSkill(output_dir=self.config.get("output_dir", "output"))
        self.evaluator = QualityEvaluatorSkill()
        self.bridge = LocalBridgeSkill(
            output_dir=self.config.get("output_dir", "output"),
            local_dir=self.config.get("local_dir", "local"),
            status_dir=self.config.get("status_dir", "status"),
            branch=self.config.get("branch", "arena/01a0a93d-test-auto-arena")
        )

    def _load_config(self):
        default_config = {
            "topic": "AI 自循环任务系统 - 自动化文档生成",
            "max_iterations": 5,
            "quality_threshold": 85,
            "output_dir": "output",
            "local_dir": "local",
            "status_dir": "status",
            "branch": "arena/01a0a93d-test-auto-arena",
            "source_agent": "https://arena.ai/agent/01a0a821-3f3c-7bbe-bf99-6e6793c45d81"
        }
        if os.path.exists(self.config_path):
            with open(self.config_path, 'r', encoding='utf-8') as f:
                try:
                    loaded = yaml.safe_load(f)
                    if loaded:
                        default_config.update(loaded)
                except Exception as e:
                    print(f"配置加载失败，使用默认配置: {e}")
        return default_config

    def run_single_iteration(self, iteration, previous_feedback=None):
        print(f"\n{'='*60}")
        print(f"开始迭代 v{iteration} - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"{'='*60}")

        topic = self.config.get("topic")

        # 1. 生成 docx
        print(f"[Loop] 生成 Docx (v{iteration})...")
        docx_result = self.docx_skill.generate(iteration=iteration, feedback=previous_feedback, topic=topic)
        print(f"[Loop] Docx 生成完成: {docx_result}")

        # 2. 生成 pptx
        print(f"[Loop] 生成 Pptx (v{iteration})...")
        pptx_result = self.pptx_skill.generate(iteration=iteration, feedback=previous_feedback, topic=topic)
        print(f"[Loop] Pptx 生成完成: {pptx_result}")

        files = [docx_result["final"], pptx_result["final"], docx_result["versioned"], pptx_result["versioned"]]

        # 3. 评估
        print(f"[Loop] 评估质量...")
        eval_result = self.evaluator.evaluate(
            docx_path=docx_result["final"],
            pptx_path=pptx_result["final"],
            iteration=iteration,
            previous_feedback=previous_feedback
        )
        print(f"[Loop] 评估结果: 得分 {eval_result['overall_score']}, 状态 {eval_result['status']}")
        print(f"[Loop] 反馈: {eval_result['feedback']}")

        # 4. 本地打通 + push
        bridge_result = self.bridge.full_cycle(iteration, files, eval_result)

        return {
            "iteration": iteration,
            "docx": docx_result,
            "pptx": pptx_result,
            "eval": eval_result,
            "bridge": bridge_result,
            "files": files
        }

    def run_loop(self):
        print(f"\n{'#'*60}")
        print(f"自循环任务启动")
        print(f"源 Agent: {self.config.get('source_agent')}")
        print(f"分支: {self.config.get('branch')}")
        print(f"最大迭代: {self.config.get('max_iterations')}, 阈值: {self.config.get('quality_threshold')}")
        print(f"{'#'*60}\n")

        max_iter = self.config.get("max_iterations", 5)
        threshold = self.config.get("quality_threshold", 85)

        previous_feedback = None
        final_result = None

        for iteration in range(1, max_iter+1):
            result = self.run_single_iteration(iteration, previous_feedback)
            final_result = result

            eval_result = result["eval"]
            
            # 判断是否终止
            if eval_result["is_pass"] or eval_result["overall_score"] >= threshold:
                print(f"\n{'*'*60}")
                print(f"✓ 迭代 v{iteration} 已达到质量阈值 ({eval_result['overall_score']} >= {threshold})")
                print(f"✓ 自循环任务完成，结果没问题！")
                print(f"{'*'*60}\n")
                break
            else:
                print(f"\n[Loop] 迭代 v{iteration} 未达阈值 ({eval_result['overall_score']} < {threshold})，准备下一轮...")
                previous_feedback = eval_result
                if iteration == max_iter:
                    print(f"\n[Loop] 已达到最大迭代 {max_iter}，循环结束。最终得分 {eval_result['overall_score']}")

        # 生成最终总结
        self._generate_final_summary(final_result)

        return final_result

    def _generate_final_summary(self, final_result):
        summary_path = os.path.join(self.config.get("status_dir", "status"), "final_summary.json")
        summary = {
            "timestamp": datetime.now().isoformat(),
            "source_agent": self.config.get("source_agent"),
            "branch": self.config.get("branch"),
            "config": self.config,
            "final_iteration": final_result["iteration"] if final_result else None,
            "final_score": final_result["eval"]["overall_score"] if final_result else None,
            "is_pass": final_result["eval"]["is_pass"] if final_result else False,
            "files": final_result["files"] if final_result else [],
            "status": "completed" if final_result and final_result["eval"]["is_pass"] else "max_iterations_reached",
            "message": "自循环任务完成，结果没问题" if final_result and final_result["eval"]["is_pass"] else "已达最大迭代，输出当前最佳结果"
        }
        with open(summary_path, 'w', encoding='utf-8') as f:
            json.dump(summary, f, ensure_ascii=False, indent=2)
        print(f"[Loop] 最终总结已生成: {summary_path}")
        print(json.dumps(summary, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    orchestrator = SelfLoopOrchestratorSkill()
    orchestrator.run_loop()
